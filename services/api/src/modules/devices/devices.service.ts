import { createHash, randomBytes } from 'node:crypto';

import { Injectable, Logger } from '@nestjs/common';
import type { Device as DeviceDto, DeviceIdentity, SignedInDevice } from '@tihe/contracts';
import { newId, type Device, type Prisma } from '@tihe/db';

import { AppError } from '../../common/app-error.js';
import { PrismaService } from '../../common/prisma.service.js';
import { isSignedIn } from './sessions.js';

type Db = PrismaService | Prisma.TransactionClient;

/**
 * Devices and their sign-in sessions (ADR-0014).
 *
 * Devices are the anchor of offline protection: content keys are wrapped to a device's public key,
 * never to a user, so this table is what decides whether a downloaded file can ever be opened. The
 * session on each row is what decides whether the device counts towards the limit of devices
 * signed in at once.
 */
@Injectable()
export class DevicesService {
  private readonly logger = new Logger(DevicesService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Registers a device, or updates the record of one already seen. Does not check the limit: that
   * happens when a session starts, inside the same locked transaction.
   *
   * Keyed on the fingerprint hash so reopening the app, or reinstalling without losing app data,
   * reuses the row. A revoked device stays revoked: an admin barred it.
   */
  async registerOrUpdate(db: Db, userId: string, identity: DeviceIdentity): Promise<Device> {
    const fingerprintHash = this.hashFingerprint(identity.fingerprint);

    const existing = await db.device.findUnique({
      where: { userId_fingerprintHash: { userId, fingerprintHash } },
    });

    if (existing) {
      if (existing.revokedAt) {
        throw new AppError('DEVICE_REVOKED', 'this device was barred for this account');
      }
      return db.device.update({
        where: { id: existing.id },
        data: {
          name: identity.name,
          // The public key can legitimately change: a keystore is cleared, or the OS rotates a
          // hardware-backed key. Accept the new one — downloads sealed to the old key are lost,
          // which is correct, because the device genuinely cannot open them any more.
          publicKey: identity.publicKey,
          appVersion: identity.appVersion ?? existing.appVersion,
          osVersion: identity.osVersion ?? existing.osVersion,
          lastSeenAt: new Date(),
        },
      });
    }

    const device = await db.device.create({
      data: {
        id: newId('device'),
        userId,
        fingerprintHash,
        platform: identity.platform,
        name: identity.name,
        publicKey: identity.publicKey,
        appVersion: identity.appVersion ?? null,
        osVersion: identity.osVersion ?? null,
        trustedAt: new Date(),
        lastSeenAt: new Date(),
      },
    });

    this.logger.log(`registered device ${device.id} (${device.platform}) for user ${userId}`);
    return device;
  }

  /** The account's devices signed in right now, other than `exceptDeviceId`. */
  signedInOthers(db: Db, userId: string, exceptDeviceId: string, now: Date): Promise<Device[]> {
    return db.device.findMany({
      where: {
        userId,
        id: { not: exceptDeviceId },
        revokedAt: null,
        sessionId: { not: null },
        sessionExpiresAt: { gt: now },
      },
      orderBy: [{ lastSeenAt: 'desc' }, { createdAt: 'desc' }],
    });
  }

  countSignedIn(db: Db, userId: string, now: Date): Promise<number> {
    return db.device.count({
      where: { userId, revokedAt: null, sessionId: { not: null }, sessionExpiresAt: { gt: now } },
    });
  }

  /**
   * Starts a new sign-in on a device. The session id goes into every access token as `sid`, so
   * ending the session ends those tokens at once rather than when they expire.
   */
  async startSession(db: Db, deviceId: string, now: Date, ttlMs: number): Promise<string> {
    const sessionId = randomBytes(18).toString('base64url');
    // A sign-in replaces whatever session the device had: its old refresh tokens die with it.
    await db.refreshToken.updateMany({
      where: { deviceId, revokedAt: null },
      data: { revokedAt: now },
    });
    await db.device.update({
      where: { id: deviceId },
      data: {
        sessionId,
        sessionStartedAt: now,
        sessionExpiresAt: new Date(now.getTime() + ttlMs),
        lastSeenAt: now,
      },
    });
    return sessionId;
  }

  /** Every refresh slides the session forward, so only an idle device times out. */
  async extendSession(db: Db, deviceId: string, until: Date): Promise<void> {
    await db.device.update({
      where: { id: deviceId },
      data: { sessionExpiresAt: until, lastSeenAt: new Date() },
    });
  }

  /**
   * Signs a device out: ends its session, its refresh tokens, its playback, and whatever it holds
   * offline.
   *
   * Expiring the downloads matters — without it, signing a device out to free a slot and signing
   * in elsewhere would leave the first device playing everything it already has, and more than N
   * devices could watch at once. An offline device learns of it at its next contact, bounded by
   * the offline window (docs/03, Layer 5).
   */
  async endSession(db: Db, deviceId: string, now: Date): Promise<void> {
    await db.device.update({
      where: { id: deviceId },
      data: { sessionId: null, sessionExpiresAt: null },
    });
    await db.refreshToken.updateMany({
      where: { deviceId, revokedAt: null },
      data: { revokedAt: now },
    });
    await db.download.updateMany({
      where: { deviceId, state: { in: ['queued', 'downloading', 'complete'] } },
      data: { state: 'expired', expiresAt: now },
    });
    await db.licenseDevice.updateMany({
      where: { deviceId, releasedAt: null },
      data: { releasedAt: now },
    });
    await db.playbackSession.updateMany({
      where: { deviceId, endedAt: null },
      data: { endedAt: now },
    });
  }

  /** Signs out every device of an account, e.g. after an admin sets a new password. */
  async endAllSessions(db: Db, userId: string, now: Date, exceptDeviceId?: string): Promise<void> {
    const devices = await db.device.findMany({
      where: {
        userId,
        sessionId: { not: null },
        ...(exceptDeviceId ? { id: { not: exceptDeviceId } } : {}),
      },
      select: { id: true },
    });
    for (const device of devices) await this.endSession(db, device.id, now);
  }

  /** Signs out one of the caller's own devices: from the account screen or another device. */
  async signOut(userId: string, deviceId: string): Promise<void> {
    const device = await this.prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw AppError.notFound('device');
    await this.prisma.$transaction((tx) => this.endSession(tx, deviceId, new Date()));
    this.logger.log(`signed out device ${deviceId} of user ${userId}`);
  }

  /** The account's devices, signed-in ones first. Revoked devices are not shown. */
  async listForUser(userId: string, currentDeviceId: string): Promise<DeviceDto[]> {
    const now = new Date();
    const devices = await this.prisma.device.findMany({
      where: { userId, revokedAt: null },
      orderBy: [{ lastSeenAt: 'desc' }, { createdAt: 'desc' }],
    });
    const dtos = await Promise.all(devices.map((d) => this.toDto(d, currentDeviceId, now)));
    return dtos.sort((a, b) => Number(b.signedIn) - Number(a.signedIn));
  }

  async toDto(
    device: Device,
    currentDeviceId: string | null,
    now = new Date(),
  ): Promise<DeviceDto> {
    const offlineVideoCount = await this.prisma.download.count({
      where: { deviceId: device.id, state: 'complete' },
    });

    return {
      id: device.id,
      platform: device.platform,
      name: device.name,
      trustedAt: device.trustedAt?.toISOString() ?? null,
      revokedAt: device.revokedAt?.toISOString() ?? null,
      lastSeenAt: device.lastSeenAt?.toISOString() ?? null,
      isCurrent: device.id === currentDeviceId,
      signedIn: isSignedIn(device, now),
      signedInAt: isSignedIn(device, now) ? (device.sessionStartedAt?.toISOString() ?? null) : null,
      offlineVideoCount,
    };
  }

  toSignedInDto(device: Device): SignedInDevice {
    return {
      id: device.id,
      platform: device.platform,
      name: device.name,
      signedInAt: device.sessionStartedAt?.toISOString() ?? null,
      lastSeenAt: device.lastSeenAt?.toISOString() ?? null,
    };
  }

  /**
   * Hashes the client-supplied fingerprint again server-side.
   *
   * The client already hashes its raw signals; hashing again means the stored value is not the same
   * string the client holds, so a database leak does not hand an attacker values they could replay
   * as another student's device.
   */
  hashFingerprint(fingerprint: string): string {
    return createHash('sha256').update(`tihe-device:${fingerprint}`).digest('hex');
  }
}
