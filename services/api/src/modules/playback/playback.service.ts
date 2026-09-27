import { createDecipheriv, createCipheriv, randomBytes } from 'node:crypto';

import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PlaybackSession, StartPlaybackBody } from '@tihe/contracts';

import { AppError } from '../../common/app-error.js';
import { newId } from '../../common/ids.js';
import { PrismaService } from '../../common/prisma.service.js';
import type { Env } from '../../config/configuration.js';
import { wrapKeyForDevice } from '../crypto/key-wrap.js';
import { LicensingService } from '../licensing/licensing.service.js';
import { StorageService } from '../storage/storage.service.js';
import { deriveWatermark, newWatermarkSeed } from './watermark.js';

/**
 * Minting protected playback sessions.
 *
 * This is the one place in the system that unwraps a content key, and it never hands out the
 * plaintext — it re-wraps for exactly one device. The full sequence is documented in
 * docs/03-content-protection.md, layer 3.
 *
 * Checks run in a deliberate order, cheapest and most-specific first, so a student gets the most
 * useful error: "not enrolled" before "licence expired" before "too many streams".
 */
@Injectable()
export class PlaybackService {
  private readonly logger = new Logger(PlaybackService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService<Env, true>,
    private readonly licensing: LicensingService,
    private readonly storage: StorageService,
  ) {}

  async start(
    userId: string,
    deviceId: string,
    videoId: string,
    body: StartPlaybackBody,
    ip?: string,
  ): Promise<PlaybackSession> {
    const video = await this.prisma.video.findUnique({
      where: { id: videoId },
      include: {
        course: true,
        assets: { orderBy: { bitrate: 'desc' } },
        contentKeys: { where: { retiredAt: null }, orderBy: { keyVersion: 'desc' }, take: 1 },
      },
    });

    if (!video) throw AppError.notFound('video');

    const enrollment = await this.prisma.enrollment.findUnique({
      where: { userId_courseId: { userId, courseId: video.courseId } },
    });
    if (!enrollment || enrollment.status !== 'active') {
      throw new AppError('NOT_ENROLLED');
    }
    if (enrollment.expiresAt && enrollment.expiresAt < new Date()) {
      throw new AppError('NOT_ENROLLED', 'enrollment expired');
    }

    if (video.status !== 'ready') {
      throw new AppError('VIDEO_NOT_READY', `video status is ${video.status}`);
    }

    const contentKey = video.contentKeys[0];
    if (!contentKey) {
      // A ready video with no key means the packaging step wrote inconsistent state. Fail loudly
      // rather than serving something unplayable.
      this.logger.error(`video ${videoId} is ready but has no active content key`);
      throw new AppError('VIDEO_NOT_READY', 'content key missing');
    }

    // Honour a client that reports a hostile environment. A patched client can lie, which is why
    // the OS-level capture blocking exists — but the honest majority is stopped here for free.
    if (body.environment && !video.course.allowCapture) {
      const env = body.environment;
      if (
        env.screenRecorderDetected ||
        env.virtualDisplayDetected ||
        env.emulator ||
        env.debuggerAttached
      ) {
        this.logger.warn(
          `blocked playback of ${videoId} for user ${userId}: hostile environment reported`,
        );
        throw new AppError('CAPTURE_ENVIRONMENT_BLOCKED', 'recording environment detected', {
          ...env,
        });
      }
    }

    const license = await this.licensing.requireValidFor(userId, videoId, deviceId);

    await this.assertStreamSlotAvailable(userId, video.course.maxConcurrentStreams, deviceId);

    const device = await this.prisma.device.findUniqueOrThrow({ where: { id: deviceId } });
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });

    // Unwrap with the KEK, then immediately re-wrap for this device. The plaintext CEK exists only
    // inside this function's scope and is never returned, logged or stored.
    const cek = this.unwrapContentKey(contentKey.wrappedKey);
    const wrappedForDevice = wrapKeyForDevice(
      cek,
      Buffer.from(device.publicKey, 'base64'),
      deviceId,
    );
    cek.fill(0);

    const rendition = video.assets.find((a) => a.label === body.rendition) ?? video.assets[0];
    if (!rendition) throw new AppError('VIDEO_NOT_READY', 'no renditions available');

    const ttl = this.config.getOrThrow('PLAYBACK_SESSION_TTL_SECONDS', { infer: true });
    const seed = newWatermarkSeed();
    const sessionId = newId('playbackSession');
    const expiresAt = new Date(Date.now() + ttl * 1000);

    await this.prisma.playbackSession.create({
      data: {
        id: sessionId,
        userId,
        deviceId,
        videoId,
        expiresAt,
        watermarkSeed: seed,
        environment: body.environment ? { ...body.environment } : undefined,
        ip: ip ?? null,
      },
    });

    const keys = StorageService.vodKeys(videoId);

    this.logger.log(
      `playback session ${sessionId} for video ${videoId} on device ${deviceId} ` +
        `(licence ${license.id}, rendition ${rendition.label})`,
    );

    return {
      sessionId,
      videoId,
      manifestUrl: await this.storage.presignGet(this.storage.vodBucket, keys.master),
      segmentBaseUrl: await this.storage.presignGet(
        this.storage.vodBucket,
        keys.renditionIndex(rendition.label),
      ),
      wrappedKey: wrappedForDevice.toString('base64'),
      encryption: {
        scheme: 'AES-128-CTR',
        ivMode: 'per-segment-sequence',
        keyId: contentKey.id,
      },
      watermark: deriveWatermark({ phone: user.phone, userId, seed }),
      // The server decides, not the client: capture blocking is course policy.
      blockCapture: !video.course.allowCapture,
      expiresAt: expiresAt.toISOString(),
      heartbeatIntervalSeconds: this.config.getOrThrow('PLAYBACK_HEARTBEAT_SECONDS', {
        infer: true,
      }),
      revocationEpoch: user.revocationEpoch,
    };
  }

  /**
   * Keeps a session alive and carries revocation back to the client.
   *
   * This is the mechanism that bounds revocation latency to one heartbeat interval — the server
   * cannot push to a device, so the device asks, frequently.
   */
  async heartbeat(userId: string, deviceId: string, sessionId: string, positionMs: number) {
    const session = await this.prisma.playbackSession.findFirst({
      where: { id: sessionId, userId, deviceId },
    });
    if (!session) throw AppError.notFound('playback session');

    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { revocationEpoch: true, status: true },
    });

    const now = new Date();

    let stop = false;
    let stopReason: string | null = null;

    if (session.endedAt) {
      stop = true;
      stopReason = 'session ended elsewhere';
    } else if (session.expiresAt < now) {
      stop = true;
      stopReason = 'session expired';
    } else if (user.status === 'suspended') {
      stop = true;
      stopReason = 'account suspended';
    } else {
      try {
        await this.licensing.requireValidFor(userId, session.videoId, deviceId);
      } catch (error) {
        stop = true;
        stopReason = error instanceof AppError ? error.code : 'licence invalid';
      }
    }

    await this.prisma.playbackSession.update({
      where: { id: sessionId },
      data: { lastHeartbeat: now, ...(stop ? { endedAt: now } : {}) },
    });

    // The heartbeat doubles as a progress ping, so a student who closes the app mid-lecture still
    // resumes near where they stopped.
    if (!stop) {
      await this.prisma.watchProgress.upsert({
        where: { userId_videoId: { userId, videoId: session.videoId } },
        create: {
          id: newId('user').replace('usr_', 'wp_'),
          userId,
          videoId: session.videoId,
          positionMs,
        },
        update: { positionMs: { set: positionMs } },
      });
    }

    return {
      ok: true as const,
      expiresAt: session.expiresAt.toISOString(),
      revocationEpoch: user.revocationEpoch,
      stop,
      stopReason,
    };
  }

  async end(userId: string, sessionId: string) {
    await this.prisma.playbackSession.updateMany({
      where: { id: sessionId, userId, endedAt: null },
      data: { endedAt: new Date() },
    });
  }

  /**
   * Enforces the concurrent-stream limit.
   *
   * Sessions from the *same* device do not count against each other: a student who force-quits the
   * app leaves a live session behind, and refusing to let them restart on the same device would be
   * a support call every time. A second device is what the limit is about.
   */
  private async assertStreamSlotAvailable(
    userId: string,
    limit: number,
    deviceId: string,
  ): Promise<void> {
    const staleBefore = new Date(
      Date.now() - this.config.getOrThrow('PLAYBACK_HEARTBEAT_SECONDS', { infer: true }) * 3000,
    );

    const active = await this.prisma.playbackSession.count({
      where: {
        userId,
        endedAt: null,
        expiresAt: { gt: new Date() },
        deviceId: { not: deviceId },
        // A session that stopped heartbeating is over, whatever its expiry says — the app was killed.
        OR: [
          { lastHeartbeat: { gt: staleBefore } },
          { lastHeartbeat: null, createdAt: { gt: staleBefore } },
        ],
      },
    });

    if (active >= limit) {
      throw new AppError('CONCURRENT_STREAM_LIMIT', `limit of ${limit} concurrent stream(s)`, {
        limit,
        active,
      });
    }
  }

  /**
   * Unwraps a content key with the KEK.
   *
   * Format: `iv(12) || ciphertext || tag(16)`, AES-256-GCM. GCM rather than CBC so a corrupted or
   * tampered row fails loudly instead of yielding garbage that then decrypts video into noise.
   */
  private unwrapContentKey(wrapped: string): Buffer {
    const kek = Buffer.from(this.config.getOrThrow('KEK_BASE64', { infer: true }), 'base64');
    const blob = Buffer.from(wrapped, 'base64');

    const iv = blob.subarray(0, 12);
    const tag = blob.subarray(blob.length - 16);
    const ciphertext = blob.subarray(12, blob.length - 16);

    const decipher = createDecipheriv('aes-256-gcm', kek, iv);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  }

  /**
   * Wraps a content key with the KEK. Used by the seed script and, from M2, by media-worker.
   *
   * Lives here alongside the unwrap so the format cannot drift between the two.
   */
  static wrapContentKeyWithKek(cek: Buffer, kekBase64: string): string {
    const kek = Buffer.from(kekBase64, 'base64');
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', kek, iv);
    const ciphertext = Buffer.concat([cipher.update(cek), cipher.final()]);
    return Buffer.concat([iv, ciphertext, cipher.getAuthTag()]).toString('base64');
  }
}
