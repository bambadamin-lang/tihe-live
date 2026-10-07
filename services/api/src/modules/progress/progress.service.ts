import { Injectable } from '@nestjs/common';
import type { WatchEvent } from '@tihe/contracts';

import { AppError } from '../../common/app-error.js';
import { newId } from '@tihe/db';
import { PrismaService } from '../../common/prisma.service.js';

/** Events claiming to be from further in the future than this are clamped. */
const MAX_CLOCK_SKEW_MS = 5 * 60 * 1000;
/** Events older than this are dropped: a genuinely offline batch is days old, not years. */
const MAX_EVENT_AGE_MS = 90 * 24 * 60 * 60 * 1000;

@Injectable()
export class ProgressService {
  constructor(private readonly prisma: PrismaService) {}

  async get(userId: string, videoId: string) {
    await this.assertEnrolled(userId, videoId);

    const row = await this.prisma.watchProgress.findUnique({
      where: { userId_videoId: { userId, videoId } },
    });

    return {
      videoId,
      positionMs: row?.positionMs ?? 0,
      completed: row?.completed ?? false,
      updatedAt: (row?.updatedAt ?? new Date()).toISOString(),
    };
  }

  /**
   * Updates the resume point.
   *
   * The position only moves forward unless the client says the video was completed, because
   * out-of-order heartbeats from a flaky connection would otherwise rewind a student's progress to
   * wherever the slowest request happened to come from.
   */
  async set(userId: string, videoId: string, positionMs: number, completed?: boolean) {
    const video = await this.assertEnrolled(userId, videoId);

    // A position past the end means a broken client or a tampered request; clamp rather than store
    // a resume point the player cannot seek to.
    const clamped = Math.max(0, Math.min(positionMs, video.durationMs || positionMs));

    const existing = await this.prisma.watchProgress.findUnique({
      where: { userId_videoId: { userId, videoId } },
    });

    const nextPosition = existing && !completed ? Math.max(existing.positionMs, clamped) : clamped;

    const row = await this.prisma.watchProgress.upsert({
      where: { userId_videoId: { userId, videoId } },
      create: {
        id: newId('user').replace('usr_', 'wp_'),
        userId,
        videoId,
        positionMs: nextPosition,
        completed: completed ?? false,
      },
      update: {
        positionMs: nextPosition,
        ...(completed !== undefined ? { completed } : {}),
      },
    });

    return {
      videoId,
      positionMs: row.positionMs,
      completed: row.completed,
      updatedAt: row.updatedAt.toISOString(),
    };
  }

  /**
   * Accepts a batch of watch events, including ones recorded offline days earlier.
   *
   * Client timestamps are kept rather than replaced with arrival time: a student who watched three
   * lectures on a long journey produces statistics that are only meaningful with the original
   * timing. They are clamped, not trusted — a far-future timestamp would corrupt every report that
   * groups by day.
   */
  async recordEvents(userId: string, deviceId: string, events: WatchEvent[]) {
    const now = Date.now();

    const enrolledVideoIds = new Set(
      (
        await this.prisma.video.findMany({
          where: {
            id: { in: [...new Set(events.map((e) => e.videoId))] },
            course: { enrollments: { some: { userId, status: 'active' } } },
          },
          select: { id: true },
        })
      ).map((v) => v.id),
    );

    const accepted: WatchEvent[] = [];
    let rejected = 0;

    for (const event of events) {
      if (!enrolledVideoIds.has(event.videoId)) {
        rejected += 1;
        continue;
      }
      const occurred = Date.parse(event.occurredAt);
      if (Number.isNaN(occurred) || occurred < now - MAX_EVENT_AGE_MS) {
        rejected += 1;
        continue;
      }
      accepted.push({
        ...event,
        occurredAt: new Date(Math.min(occurred, now + MAX_CLOCK_SKEW_MS)).toISOString(),
      });
    }

    if (accepted.length > 0) {
      await this.prisma.watchEvent.createMany({
        data: accepted.map((e) => ({
          id: newId('user').replace('usr_', 'we_'),
          userId,
          // Trust the authenticated device over the body: a client could otherwise attribute its
          // activity to another of the user's devices.
          deviceId,
          videoId: e.videoId,
          event: e.event,
          positionMs: e.positionMs,
          occurredAt: new Date(e.occurredAt),
          offline: e.offline,
        })),
      });

      // Advance the resume point from the newest position per video, so an offline batch leaves the
      // student where they actually stopped.
      const newestByVideo = new Map<string, WatchEvent>();
      for (const e of accepted) {
        const current = newestByVideo.get(e.videoId);
        if (!current || Date.parse(e.occurredAt) > Date.parse(current.occurredAt)) {
          newestByVideo.set(e.videoId, e);
        }
      }
      for (const [videoId, e] of newestByVideo) {
        await this.set(userId, videoId, e.positionMs, e.event === 'complete' ? true : undefined);
      }
    }

    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { revocationEpoch: true },
    });

    return {
      accepted: accepted.length,
      rejected,
      // Returned on every sync so a device whose licence was revoked while offline finds out here,
      // without needing a separate call.
      revocationEpoch: user.revocationEpoch,
    };
  }

  private async assertEnrolled(userId: string, videoId: string) {
    const video = await this.prisma.video.findFirst({
      where: { id: videoId, course: { enrollments: { some: { userId, status: 'active' } } } },
      select: { id: true, durationMs: true },
    });
    if (!video) throw new AppError('NOT_ENROLLED', "not enrolled in this video's course");
    return video;
  }
}
