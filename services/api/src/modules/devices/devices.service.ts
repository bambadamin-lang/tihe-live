import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Device as DeviceDto, DeviceIdentity } from '@tihe/contracts';
import type { Device } from '@prisma/client';
import { createHash } from 'node:crypto';

import { AppError } from '../../common/app-error.js';
import { newId } from '../../common/ids.js';
import { PrismaService } from '../../common/prisma.service.js';
import type { Env } from '../../config/configuration.js';

/**
 * Device registration and the device allowance.
 *
 * Devices are the anchor of offline protection: content keys are wrapped to a device's public key,
 * never to a user, so this table is what decides whether a downloaded file can ever be opened.
 */
@Injectable()
export class DevicesService {
  private readonly logger = new Logger(DevicesService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService<Env, true>,
  ) {}

  /**
   * Registers a device, or updates the record of one already seen.
   *
   * Keyed on the fingerprint hash so reopening the app, or reinstalling without losing app data,
   * does not consume a second slot. A returning device that was revoked stays revoked — the
   * student must release it deliberately.
   */
  async registerOrUpdate(userId: string, identity: DeviceIdentity): Promise<Device> {
    const fingerprintHash = this.hashFingerprint(identity.fingerprint);

    const existing = await this.prisma.device.findUnique({
      where: { userId_fingerprintHash: { userId, fingerprintHash } },
    });

    if (existing) {
      if (existing.revokedAt) {
        throw new AppError('DEVICE_REVOKED', 'this device was released and must be re-added');
      }
      return this.prisma.device.update({
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

    await this.assertSlotAvailable(userId);

    const device = await this.prisma.device.create({
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

  /**
   * Enforces the device allowance.
   *
   * Counted over non-revoked devices only, so releasing a device genuinely frees the slot rather
   * than leaving the student stuck with a number they cannot reduce.
   */
  private async assertSlotAvailable(userId: string): Promise<void> {
    const limit = await this.limitFor(userId);
    const active = await this.prisma.device.count({ where: { userId, revokedAt: null } });

    if (active >= limit) {
      throw new AppError('DEVICE_LIMIT_REACHED', `device limit of ${limit} reached`, {
        limit,
        active,
      });
    }
  }

  /**
   * The allowance for a user: the most generous of their enrolled courses, falling back to the
   * global default.
   *
   * Taking the maximum rather than the minimum is deliberate — a student enrolled in one strict
   * course and one lenient one should not be locked down to the strict course's limit for
   * everything. Per-course enforcement happens at playback, where the course is known.
   */
  async limitFor(userId: string): Promise<number> {
    const fallback = this.config.getOrThrow('DEFAULT_MAX_DEVICES', { infer: true });

    const result = await this.prisma.enrollment.findMany({
      where: { userId, status: 'active' },
      select: { course: { select: { maxDevices: true } } },
    });

    if (result.length === 0) return fallback;
    return Math.max(...result.map((e) => e.course.maxDevices));
  }

  async listForUser(userId: string, currentDeviceId: string): Promise<DeviceDto[]> {
    const devices = await this.prisma.device.findMany({
      where: { userId, revokedAt: null },
      orderBy: { createdAt: 'asc' },
    });

    return Promise.all(devices.map((d) => this.toDto(d, currentDeviceId)));
  }

  /**
   * Releases a device: revokes it, kills its sessions, and expires whatever it holds offline.
   *
   * Expiring the downloads matters — without it, a student could release a device to free a slot
   * while the released machine keeps playing everything it already has.
   */
  async release(userId: string, deviceId: string): Promise<void> {
    const device = await this.prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw AppError.notFound('device');

    const now = new Date();

    await this.prisma.$transaction([
      this.prisma.device.update({ where: { id: deviceId }, data: { revokedAt: now } }),
      this.prisma.refreshToken.updateMany({
        where: { deviceId, revokedAt: null },
        data: { revokedAt: now },
      }),
      this.prisma.download.updateMany({
        where: { deviceId, state: { in: ['queued', 'downloading', 'complete'] } },
        data: { state: 'expired', expiresAt: now },
      }),
      this.prisma.licenseDevice.updateMany({
        where: { deviceId, releasedAt: null },
        data: { releasedAt: now },
      }),
      this.prisma.playbackSession.updateMany({
        where: { deviceId, endedAt: null },
        data: { endedAt: now },
      }),
    ]);

    this.logger.log(`released device ${deviceId} for user ${userId}`);
  }

  async toDto(device: Device, currentDeviceId: string): Promise<DeviceDto> {
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
      offlineVideoCount,
    };
  }

  /**
   * Hashes the client-supplied fingerprint again server-side.
   *
   * The client already hashes its raw signals; hashing again means the stored value is not the same
   * string the client holds, so a database leak does not hand an attacker values they could replay
   * as another student's device.
   */
  private hashFingerprint(fingerprint: string): string {
    return createHash('sha256').update(`tihe-device:${fingerprint}`).digest('hex');
  }
}
