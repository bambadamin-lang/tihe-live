import { randomBytes, randomInt, createHash } from 'node:crypto';

import { Inject, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type { AuthSession, DeviceIdentity, TokenPair } from '@tihe/contracts';
import { maskPhone } from '@tihe/contracts';
import * as argon2 from 'argon2';

import { AppError } from '../../common/app-error.js';
import { newId } from '../../common/ids.js';
import { PrismaService } from '../../common/prisma.service.js';
import type { Env } from '../../config/configuration.js';
import { DevicesService } from '../devices/devices.service.js';
import {
  checkOtpState,
  decideOtpRequest,
  generateOtpCode,
  type OtpPolicyConfig,
} from './otp.policy.js';
import { SMS_PROVIDER, type SmsProvider } from './sms.provider.js';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService<Env, true>,
    private readonly jwt: JwtService,
    private readonly devices: DevicesService,
    @Inject(SMS_PROVIDER) private readonly sms: SmsProvider,
  ) {}

  private get policy(): OtpPolicyConfig {
    return {
      ttlSeconds: this.config.getOrThrow('OTP_TTL_SECONDS', { infer: true }),
      resendAfterSeconds: this.config.getOrThrow('OTP_RESEND_AFTER_SECONDS', { infer: true }),
      maxPerPhonePerHour: this.config.getOrThrow('OTP_MAX_PER_PHONE_PER_HOUR', { infer: true }),
      maxPerIpPerHour: this.config.getOrThrow('OTP_MAX_PER_IP_PER_HOUR', { infer: true }),
      maxAttempts: this.config.getOrThrow('OTP_MAX_ATTEMPTS', { infer: true }),
    };
  }

  /**
   * Issues an OTP.
   *
   * The response is identical whether or not the number belongs to a registered student. Anything
   * else turns this endpoint into a way to enumerate who studies at the institute.
   */
  async requestOtp(phone: string, ip: string | undefined, userAgent: string | undefined) {
    const now = new Date();
    const hourAgo = new Date(now.getTime() - 3_600_000);
    const policy = this.policy;

    const [recentForPhone, recentForIpCount] = await Promise.all([
      this.prisma.otpCode.findMany({
        where: { phone, createdAt: { gt: hourAgo } },
        select: { createdAt: true, consumedAt: true },
      }),
      ip
        ? this.prisma.otpCode.count({ where: { ip, createdAt: { gt: hourAgo } } })
        : Promise.resolve(0),
    ]);

    const decision = decideOtpRequest(now, policy, recentForPhone, recentForIpCount);
    if (!decision.allowed) {
      this.logger.warn(`OTP refused for ${maskPhone(phone)}: ${decision.reason}`);
      throw new AppError('OTP_RATE_LIMITED', decision.reason, {
        ...(decision.reason === 'resend_too_soon'
          ? { retryAfterSeconds: decision.retryAfterSeconds }
          : {}),
      });
    }

    const code = generateOtpCode(this.config.getOrThrow('OTP_LENGTH', { infer: true }), (max) =>
      randomInt(max),
    );

    const record = await this.prisma.otpCode.create({
      data: {
        id: newId('user').replace('usr_', 'otp_'),
        phone,
        codeHash: await this.hashOtp(phone, code),
        expiresAt: new Date(now.getTime() + policy.ttlSeconds * 1000),
        ip: ip ?? null,
        userAgent: userAgent?.slice(0, 256) ?? null,
      },
    });

    await this.sms.sendOtp(phone, code);

    return {
      requestId: record.id,
      expiresInSeconds: policy.ttlSeconds,
      resendAfterSeconds: policy.resendAfterSeconds,
      // Only the console driver exposes the code, and only so local development does not need a
      // real SMS gateway.
      ...(this.sms.exposesCode ? { devCode: code } : {}),
    };
  }

  /**
   * Verifies a code and signs the user in, registering the device if it is new.
   *
   * Device registration happens here rather than in a separate call so a student never ends up
   * authenticated but unable to play anything for lack of a registered device.
   */
  async verifyOtp(
    phone: string,
    code: string,
    device: DeviceIdentity,
    ip?: string,
  ): Promise<AuthSession> {
    const now = new Date();
    const policy = this.policy;

    const record = await this.prisma.otpCode.findFirst({
      where: { phone },
      orderBy: { createdAt: 'desc' },
    });

    if (!record) {
      throw new AppError('OTP_INVALID', 'no code was requested for this number');
    }

    const state = checkOtpState(now, policy, record);
    if (state === 'expired') throw new AppError('OTP_EXPIRED');
    if (state === 'consumed') throw new AppError('OTP_INVALID', 'code already used');
    if (state === 'too_many_attempts') {
      throw new AppError('OTP_RATE_LIMITED', 'too many attempts for this code');
    }

    const matches = await argon2.verify(record.codeHash, this.otpMaterial(phone, code));
    if (!matches) {
      // Count the failure before returning, so a brute-force attempt exhausts the allowance even
      // though each individual response looks the same.
      await this.prisma.otpCode.update({
        where: { id: record.id },
        data: { attemptCount: { increment: 1 } },
      });
      throw new AppError('OTP_INVALID');
    }

    await this.prisma.otpCode.update({
      where: { id: record.id },
      data: { consumedAt: now, attemptCount: { increment: 1 } },
    });

    const user =
      (await this.prisma.user.findUnique({ where: { phone } })) ??
      (await this.prisma.user.create({ data: { id: newId('user'), phone } }));

    if (user.status === 'suspended') {
      throw AppError.forbidden('account suspended');
    }

    const registered = await this.devices.registerOrUpdate(user.id, device);
    const tokens = await this.issueTokens(user.id, registered.id);

    // The IP is logged for abuse investigation — a single address signing in as many students is
    // the pattern worth seeing. The phone number is masked, as everywhere.
    this.logger.log(
      `sign-in ${maskPhone(phone)} on ${registered.platform} (${registered.id}) from ${ip ?? 'unknown'}`,
    );

    return {
      tokens,
      user: {
        id: user.id,
        phoneMasked: maskPhone(user.phone),
        displayName: user.displayName,
        role: user.role,
        status: user.status,
        createdAt: user.createdAt.toISOString(),
      },
      device: await this.devices.toDto(registered, registered.id),
    };
  }

  /**
   * Rotates a refresh token.
   *
   * Refresh tokens are single-use. Presenting a consumed one is not a race to tolerate — it means
   * the token was captured, so the entire device session is revoked and the client must sign in
   * again. Losing a legitimate session occasionally is the right trade against a silent takeover.
   */
  async refresh(refreshToken: string): Promise<TokenPair> {
    const tokenHash = this.hashToken(refreshToken);
    const stored = await this.prisma.refreshToken.findUnique({
      where: { tokenHash },
      include: { device: true },
    });

    if (!stored) throw new AppError('TOKEN_EXPIRED', 'unknown refresh token');

    if (stored.usedAt || stored.revokedAt) {
      this.logger.warn(
        `refresh token reuse detected for device ${stored.deviceId}; revoking session`,
      );
      await this.prisma.refreshToken.updateMany({
        where: { deviceId: stored.deviceId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
      throw new AppError('TOKEN_EXPIRED', 'refresh token already used');
    }

    if (stored.expiresAt < new Date()) {
      throw new AppError('TOKEN_EXPIRED');
    }

    if (stored.device.revokedAt) {
      throw new AppError('DEVICE_REVOKED');
    }

    await this.prisma.refreshToken.update({
      where: { id: stored.id },
      data: { usedAt: new Date() },
    });

    return this.issueTokens(stored.userId, stored.deviceId);
  }

  async logout(deviceId: string): Promise<void> {
    await this.prisma.refreshToken.updateMany({
      where: { deviceId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  private async issueTokens(userId: string, deviceId: string): Promise<TokenPair> {
    const accessTtl = this.config.getOrThrow('ACCESS_TOKEN_TTL', { infer: true });
    const refreshTtl = this.config.getOrThrow('REFRESH_TOKEN_TTL', { infer: true });

    // The device id is inside the access token, so every downstream check — playback, downloads,
    // licences — knows which device is asking without trusting a body parameter.
    const accessToken = await this.jwt.signAsync(
      { sub: userId, did: deviceId },
      { expiresIn: accessTtl },
    );

    const refreshToken = randomBytes(48).toString('base64url');
    const refreshExpiresAt = new Date(Date.now() + parseDuration(refreshTtl));

    await this.prisma.refreshToken.create({
      data: {
        id: newId('user').replace('usr_', 'rt_'),
        userId,
        deviceId,
        tokenHash: this.hashToken(refreshToken),
        expiresAt: refreshExpiresAt,
      },
    });

    const decoded = this.jwt.decode(accessToken) as { exp: number };

    return {
      accessToken,
      refreshToken,
      accessExpiresAt: new Date(decoded.exp * 1000).toISOString(),
      refreshExpiresAt: refreshExpiresAt.toISOString(),
    };
  }

  /** Argon2 with a server-side pepper: a stolen database cannot be brute-forced for live codes. */
  private async hashOtp(phone: string, code: string): Promise<string> {
    return argon2.hash(this.otpMaterial(phone, code), { type: argon2.argon2id });
  }

  /** Binding the phone into the hash stops a code issued for one number verifying another. */
  private otpMaterial(phone: string, code: string): string {
    const pepper = this.config.getOrThrow('OTP_PEPPER', { infer: true });
    return `${pepper}:${phone}:${code}`;
  }

  /**
   * Refresh tokens are stored hashed, not encrypted: the API never needs to read one back, only to
   * recognise it. SHA-256 rather than Argon2 because these are 48 random bytes, not a password —
   * there is nothing to brute-force, and the lookup is on the hot path.
   */
  private hashToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }
}

/** Parses the `15m` / `30d` forms used in configuration. */
export function parseDuration(value: string): number {
  const match = /^(\d+)([smhd])$/.exec(value.trim());
  if (!match) throw new Error(`invalid duration: ${value}`);
  const amount = Number(match[1]);
  const unit = match[2];
  const multipliers: Record<string, number> = {
    s: 1000,
    m: 60_000,
    h: 3_600_000,
    d: 86_400_000,
  };
  const multiplier = unit === undefined ? undefined : multipliers[unit];
  if (multiplier === undefined) throw new Error(`invalid duration unit in: ${value}`);
  return amount * multiplier;
}
