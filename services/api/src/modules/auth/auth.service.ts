import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type {
  AuthSession,
  ChangePasswordBody,
  DeviceIdentity,
  DeviceLimitDetails,
  LoginBody,
  ReplaceDeviceBody,
  TokenPair,
} from '@tihe/contracts';
import { maskPhone } from '@tihe/contracts';
import { newId, type User } from '@tihe/db';

import { AppError } from '../../common/app-error.js';
import { PrismaService } from '../../common/prisma.service.js';
import type { Env } from '../../config/configuration.js';
import { DevicesService } from '../devices/devices.service.js';
import { effectiveDeviceLimit } from '../devices/sessions.js';
import { SettingsService } from '../settings/settings.service.js';
import { decideLoginAttempt, type LoginPolicy } from './login.policy.js';
import { checkPasswordPolicy, PasswordHasher } from '@tihe/crypto';
import { hashRefreshToken, TokenService } from './tokens.js';

/**
 * Phone + password sign-in (ADR-0013) with a limit on devices signed in at once (ADR-0014).
 */
@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService<Env, true>,
    private readonly tokens: TokenService,
    private readonly devices: DevicesService,
    private readonly settings: SettingsService,
    private readonly hasher: PasswordHasher,
  ) {}

  private get policy(): LoginPolicy {
    return {
      windowMinutes: this.config.getOrThrow('LOGIN_WINDOW_MINUTES', { infer: true }),
      maxFailuresPerPhone: this.config.getOrThrow('LOGIN_MAX_FAILURES_PER_PHONE', { infer: true }),
      maxFailuresPerIp: this.config.getOrThrow('LOGIN_MAX_FAILURES_PER_IP', { infer: true }),
    };
  }

  /**
   * Signs in with phone and password.
   *
   * An unknown number and a wrong password give the same INVALID_CREDENTIALS after the same work,
   * so this endpoint cannot be used to find out who studies at the institute.
   */
  async login(body: LoginBody, ip: string | undefined): Promise<AuthSession> {
    const now = new Date();
    const since = new Date(now.getTime() - this.policy.windowMinutes * 60_000);

    const [phoneFailures, ipFailures] = await Promise.all([
      this.prisma.loginAttempt.findMany({
        where: { phone: body.phone, succeeded: false, createdAt: { gt: since } },
        select: { createdAt: true },
      }),
      ip
        ? this.prisma.loginAttempt.findMany({
            where: { ip, succeeded: false, createdAt: { gt: since } },
            select: { createdAt: true },
          })
        : Promise.resolve([]),
    ]);

    const decision = decideLoginAttempt(
      now,
      this.policy,
      phoneFailures.map((f) => f.createdAt),
      ipFailures.map((f) => f.createdAt),
    );
    if (!decision.allowed) {
      this.logger.warn(`sign-in refused for ${maskPhone(body.phone)}: rate limited`);
      throw new AppError('LOGIN_RATE_LIMITED', 'too many failed sign-ins', {
        retryAfterSeconds: decision.retryAfterSeconds,
      });
    }

    const user = await this.prisma.user.findUnique({ where: { phone: body.phone } });
    const ok = user?.passwordHash
      ? await this.hasher.verify(user.passwordHash, body.password)
      : await this.hasher.verifyAgainstNothing(body.password);

    await this.prisma.loginAttempt.create({
      data: { id: newId('loginAttempt'), phone: body.phone, ip: ip ?? null, succeeded: ok },
    });

    if (!ok || !user) throw new AppError('INVALID_CREDENTIALS');
    if (user.status === 'suspended') throw new AppError('ACCOUNT_SUSPENDED');

    const session = await this.signInDevice(user, body.device, now);
    this.logger.log(
      `sign-in ${maskPhone(user.phone)} on ${session.device.platform} (${session.device.id}) ` +
        `from ${ip ?? 'unknown'}`,
    );
    return session;
  }

  /**
   * Finishes a sign-in that hit the device limit: signs the chosen device out, then signs this
   * one in. The ticket proves the password was right a few minutes ago, on this device.
   */
  async replaceDevice(body: ReplaceDeviceBody): Promise<AuthSession> {
    const ticket = await this.tokens.verifyDeviceLimitTicket(body.ticket);
    if (
      !ticket ||
      ticket.fingerprintHash !== this.devices.hashFingerprint(body.device.fingerprint)
    ) {
      throw new AppError('TOKEN_EXPIRED', 'device-limit ticket invalid or expired');
    }

    const user = await this.prisma.user.findUnique({ where: { id: ticket.userId } });
    if (!user) throw new AppError('TOKEN_EXPIRED', 'device-limit ticket invalid or expired');
    if (user.status === 'suspended') throw new AppError('ACCOUNT_SUSPENDED');

    const session = await this.signInDevice(user, body.device, new Date(), body.signOutDeviceId);
    this.logger.log(
      `sign-in ${maskPhone(user.phone)} on ${session.device.id} after signing out ` +
        `${body.signOutDeviceId}`,
    );
    return session;
  }

  /**
   * Registers the device if it is new and starts a session on it, or refuses with the devices
   * already signed in.
   *
   * The user row is locked for the whole check, so two devices signing in at the same moment
   * cannot both take the last slot.
   */
  private async signInDevice(
    user: User,
    identity: DeviceIdentity,
    now: Date,
    signOutDeviceId?: string,
  ): Promise<AuthSession> {
    const result = await this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM users WHERE id = ${user.id} FOR UPDATE`;

      const device = await this.devices.registerOrUpdate(tx, user.id, identity);

      if (signOutDeviceId) {
        const target = await tx.device.findFirst({
          where: { id: signOutDeviceId, userId: user.id },
        });
        if (!target) throw AppError.notFound('device');
        if (target.id !== device.id) await this.devices.endSession(tx, target.id, now);
      }

      const limit = effectiveDeviceLimit(
        user.maxDevices,
        await this.settings.defaultMaxDevices(tx),
      );
      const others = await this.devices.signedInOthers(tx, user.id, device.id, now);

      if (others.length >= limit) {
        return {
          kind: 'refused',
          limit,
          devices: others.map((d) => this.devices.toSignedInDto(d)),
          fingerprintHash: device.fingerprintHash,
        } as const;
      }

      const sessionId = await this.devices.startSession(
        tx,
        device.id,
        now,
        this.tokens.refreshTtlMs,
      );
      const tokens = await this.tokens.issue(tx, {
        userId: user.id,
        role: user.role,
        deviceId: device.id,
        sessionId,
      });
      return { kind: 'signed-in', deviceId: device.id, tokens } as const;
    });

    if (result.kind === 'refused') {
      // Thrown after the transaction, so a device seen for the first time is still registered and
      // the ticket refers to a row that exists.
      const { ticket, expiresAt } = await this.tokens.deviceLimitTicket(
        user.id,
        result.fingerprintHash,
      );
      const details: DeviceLimitDetails = {
        limit: result.limit,
        devices: result.devices,
        ticket,
        ticketExpiresAt: expiresAt,
      };
      throw new AppError('DEVICE_LIMIT_REACHED', `device limit of ${details.limit} reached`, {
        ...details,
      });
    }

    const device = await this.prisma.device.findUniqueOrThrow({ where: { id: result.deviceId } });
    return {
      tokens: result.tokens,
      user: this.userDto(user),
      device: await this.devices.toDto(device, device.id),
    };
  }

  /**
   * Rotates a refresh token and slides the session forward.
   *
   * Refresh tokens are single-use. Presenting a consumed one is not a race to tolerate — it means
   * the token was captured, so the device is signed out and must sign in again.
   */
  async refresh(refreshToken: string): Promise<TokenPair> {
    const now = new Date();
    const stored = await this.prisma.refreshToken.findUnique({
      where: { tokenHash: hashRefreshToken(refreshToken) },
      include: { device: true, user: true },
    });

    if (!stored) throw new AppError('TOKEN_EXPIRED', 'unknown refresh token');

    if (stored.usedAt || stored.revokedAt) {
      if (stored.usedAt && !stored.revokedAt) {
        this.logger.warn(`refresh token reuse on device ${stored.deviceId}; signing it out`);
        await this.prisma.$transaction((tx) => this.devices.endSession(tx, stored.deviceId, now));
      }
      throw new AppError(
        stored.device.sessionId ? 'TOKEN_EXPIRED' : 'DEVICE_SIGNED_OUT',
        'refresh token no longer valid',
      );
    }
    if (stored.expiresAt <= now) throw new AppError('TOKEN_EXPIRED');
    if (stored.device.revokedAt) throw new AppError('DEVICE_REVOKED');
    if (!stored.device.sessionId) throw new AppError('DEVICE_SIGNED_OUT');
    if (stored.user.status === 'suspended') throw new AppError('ACCOUNT_SUSPENDED');

    const sessionId = stored.device.sessionId;
    return this.prisma.$transaction(async (tx) => {
      // Conditional on still being unused, so two concurrent refreshes cannot both succeed.
      const claimed = await tx.refreshToken.updateMany({
        where: { id: stored.id, usedAt: null, revokedAt: null },
        data: { usedAt: now },
      });
      if (claimed.count !== 1) throw new AppError('TOKEN_EXPIRED', 'refresh token already used');

      await this.devices.extendSession(
        tx,
        stored.deviceId,
        new Date(now.getTime() + this.tokens.refreshTtlMs),
      );
      return this.tokens.issue(tx, {
        userId: stored.userId,
        role: stored.user.role,
        deviceId: stored.deviceId,
        sessionId,
      });
    });
  }

  /** Signs this device out, which frees its slot. */
  async logout(deviceId: string): Promise<void> {
    await this.prisma.$transaction((tx) => this.devices.endSession(tx, deviceId, new Date()));
  }

  async changePassword(userId: string, deviceId: string, body: ChangePasswordBody): Promise<void> {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    const ok = user.passwordHash
      ? await this.hasher.verify(user.passwordHash, body.currentPassword)
      : false;
    if (!ok) throw new AppError('INVALID_CREDENTIALS', 'current password is wrong');

    const problem = checkPasswordPolicy(body.newPassword, user.phone);
    if (problem) throw new AppError('PASSWORD_TOO_WEAK', problem);
    if (body.newPassword === body.currentPassword) {
      throw new AppError('PASSWORD_TOO_WEAK', 'same as the current password');
    }

    const now = new Date();
    const passwordHash = await this.hasher.hash(body.newPassword);
    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: userId },
        data: { passwordHash, passwordChangedAt: now, mustChangePassword: false },
      });
      if (body.signOutOtherDevices) await this.devices.endAllSessions(tx, userId, now, deviceId);
    });
    this.logger.log(`password changed for user ${userId}`);
  }

  userDto(user: User): AuthSession['user'] {
    return {
      id: user.id,
      phoneMasked: maskPhone(user.phone),
      displayName: user.displayName,
      role: user.role,
      status: user.status,
      mustChangePassword: user.mustChangePassword,
      createdAt: user.createdAt.toISOString(),
    };
  }
}
