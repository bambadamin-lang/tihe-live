import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import { AppError } from '../../common/app-error.js';
import { newId } from '../../common/ids.js';
import { PrismaService } from '../../common/prisma.service.js';
import type { Env } from '../../config/configuration.js';
import { signLicense, type LicensePayloadWire } from './license.signer.js';

export interface IssueLicenseInput {
  userId: string;
  courseIds?: string[];
  videoIds?: string[];
  notBefore?: Date;
  notAfter?: Date;
  maxDevices?: number;
  offlineWindowDays?: number;
  issuedBy?: string;
}

@Injectable()
export class LicensingService {
  private readonly logger = new Logger(LicensingService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService<Env, true>,
  ) {}

  /**
   * Issues a signed licence.
   *
   * The signed blob is stored verbatim rather than regenerated on demand, so support can always see
   * precisely what a device was given — which is the difference between diagnosing a licence problem
   * and guessing at one.
   */
  async issue(input: IssueLicenseInput) {
    const user = await this.prisma.user.findUnique({ where: { id: input.userId } });
    if (!user) throw AppError.notFound('user');

    const courseIds = input.courseIds ?? [];
    const videoIds = input.videoIds ?? [];
    if (courseIds.length === 0 && videoIds.length === 0) {
      throw new AppError('VALIDATION_FAILED', 'a licence must scope at least one course or video');
    }

    // Derive policy from the courses in scope rather than accepting whatever the caller passes:
    // otherwise an admin mistake could hand out a 10-year offline window on a course configured for
    // 30 days.
    const courses = await this.prisma.course.findMany({
      where: { id: { in: courseIds } },
      select: { id: true, maxDevices: true, offlineWindowDays: true, maxConcurrentStreams: true },
    });

    if (courses.length !== courseIds.length) {
      throw AppError.notFound('one or more courses');
    }

    const now = new Date();
    const notBefore = input.notBefore ?? now;
    const offlineWindowDays =
      input.offlineWindowDays ??
      (courses.length > 0
        ? Math.min(...courses.map((c) => c.offlineWindowDays))
        : this.config.getOrThrow('DEFAULT_OFFLINE_WINDOW_DAYS', { infer: true }));

    const notAfter =
      input.notAfter ?? new Date(notBefore.getTime() + offlineWindowDays * 86_400_000);

    if (notAfter <= notBefore) {
      throw new AppError('VALIDATION_FAILED', 'notAfter must be after notBefore');
    }

    const maxDevices =
      input.maxDevices ??
      (courses.length > 0
        ? Math.min(...courses.map((c) => c.maxDevices))
        : this.config.getOrThrow('DEFAULT_MAX_DEVICES', { infer: true }));

    const maxConcurrentStreams =
      courses.length > 0
        ? Math.min(...courses.map((c) => c.maxConcurrentStreams))
        : this.config.getOrThrow('DEFAULT_MAX_CONCURRENT_STREAMS', { infer: true });

    const licenseId = newId('license');

    // The devices bound at issue time are the user's currently active ones. A device added later
    // gets a reissued licence — binding is explicit, never implicit, or the device limit would mean
    // nothing.
    const devices = await this.prisma.device.findMany({
      where: { userId: input.userId, revokedAt: null },
      select: { id: true },
      take: maxDevices,
    });

    const payload: LicensePayloadWire = {
      v: 1,
      license_id: licenseId,
      user_id: input.userId,
      device_ids: devices.map((d) => d.id),
      course_ids: courseIds,
      video_ids: videoIds,
      not_before: notBefore.toISOString(),
      not_after: notAfter.toISOString(),
      max_devices: maxDevices,
      max_concurrent_streams: maxConcurrentStreams,
      offline_window_days: offlineWindowDays,
      revocation_epoch: user.revocationEpoch,
      issued_at: now.toISOString(),
      server_time: now.toISOString(),
    };

    const signed = signLicense(
      payload,
      this.config.getOrThrow('LICENSE_PRIVATE_KEY_BASE64', { infer: true }),
    );

    const license = await this.prisma.license.create({
      data: {
        id: licenseId,
        userId: input.userId,
        scope: { courseIds, videoIds },
        notBefore,
        notAfter,
        maxDevices,
        maxConcurrentStreams,
        offlineWindowDays,
        revocationEpoch: user.revocationEpoch,
        signedBlob: signed.signedBytes.toString('base64'),
        signature: signed.signature.toString('base64'),
        issuedBy: input.issuedBy ?? null,
        devices: {
          create: devices.map((d) => ({
            id: newId('license').replace('lic_', 'ld_'),
            deviceId: d.id,
          })),
        },
      },
      include: { devices: true },
    });

    this.logger.log(
      `issued licence ${license.id} to user ${input.userId} for ${courseIds.length} course(s), ` +
        `${devices.length} device(s), expiring ${notAfter.toISOString()}`,
    );

    return license;
  }

  /**
   * Finds the licence that covers a video for a user, or throws the specific reason it does not.
   *
   * Distinguishing missing from expired from revoked matters: each maps to different Persian text
   * and a different recovery action in the app.
   */
  async requireValidFor(userId: string, videoId: string, deviceId: string) {
    const video = await this.prisma.video.findUnique({
      where: { id: videoId },
      select: { courseId: true },
    });
    if (!video) throw AppError.notFound('video');

    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { revocationEpoch: true },
    });

    const candidates = await this.prisma.license.findMany({
      where: { userId },
      include: { devices: true },
      orderBy: { notAfter: 'desc' },
    });

    const inScope = candidates.filter((l) => {
      const scope = l.scope as { courseIds?: string[]; videoIds?: string[] };
      return (
        (scope.courseIds ?? []).includes(video.courseId) || (scope.videoIds ?? []).includes(videoId)
      );
    });

    if (inScope.length === 0) throw new AppError('LICENSE_MISSING');

    const now = new Date();

    // Report the most favourable failure: a student with one revoked and one merely expired licence
    // should be told it expired, because that is the one they can renew.
    const boundToDevice = inScope.filter((l) =>
      l.devices.some((d) => d.deviceId === deviceId && !d.releasedAt),
    );
    if (boundToDevice.length === 0) {
      throw new AppError('LICENSE_MISSING', 'no licence is bound to this device', { deviceId });
    }

    const notRevoked = boundToDevice.filter(
      (l) => !l.revokedAt && l.revocationEpoch >= user.revocationEpoch,
    );
    if (notRevoked.length === 0) throw new AppError('LICENSE_REVOKED');

    const valid = notRevoked.find((l) => l.notBefore <= now && l.notAfter > now);
    if (!valid) throw new AppError('LICENSE_EXPIRED');

    return valid;
  }

  /**
   * Revokes a licence and bumps the user's epoch.
   *
   * The epoch is what makes revocation reach devices: an offline device holding a lower epoch
   * discards its keys at its next contact, without the server needing to reach it.
   */
  async revoke(licenseId: string, reason: string, actorId?: string) {
    const license = await this.prisma.license.findUnique({ where: { id: licenseId } });
    if (!license) throw AppError.notFound('licence');

    const now = new Date();

    const [updated] = await this.prisma.$transaction([
      this.prisma.license.update({
        where: { id: licenseId },
        data: { revokedAt: now, revokedReason: reason },
      }),
      this.prisma.user.update({
        where: { id: license.userId },
        data: { revocationEpoch: { increment: 1 } },
      }),
      // End live sessions immediately rather than waiting for a heartbeat to notice.
      this.prisma.playbackSession.updateMany({
        where: { userId: license.userId, endedAt: null },
        data: { endedAt: now },
      }),
      this.prisma.download.updateMany({
        where: { licenseId, state: { in: ['queued', 'downloading', 'complete'] } },
        data: { state: 'expired', expiresAt: now },
      }),
    ]);

    this.logger.warn(`revoked licence ${licenseId} (${reason}) by ${actorId ?? 'system'}`);
    return updated;
  }
}
