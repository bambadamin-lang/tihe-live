import { Injectable } from '@nestjs/common';
import type {
  CourseDetail,
  CourseSummary,
  SearchResult,
  Term,
  VideoDetail,
  VideoSummary,
} from '@tihe/contracts';
import type { Prisma } from '@tihe/db';

import { AppError } from '../../common/app-error.js';
import { PrismaService } from '../../common/prisma.service.js';
import { StorageService } from '../storage/storage.service.js';
import { prepareSearchQuery } from './search.js';

/**
 * Read model for the student's library.
 *
 * One rule governs every method here: **nothing is returned that the caller is not enrolled in.**
 * The catalogue is not a discovery surface — an unenrolled course does not appear as locked, it
 * does not appear at all, and requesting it directly yields a 404. Leaking the existence and
 * titles of every course to every signed-in user would be a quiet information disclosure.
 */
@Injectable()
export class CatalogService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
  ) {}

  async terms(userId: string): Promise<Term[]> {
    const terms = await this.prisma.term.findMany({
      where: { courses: { some: { enrollments: { some: { userId, status: 'active' } } } } },
      orderBy: { startsAt: 'desc' },
    });

    return terms.map((t) => ({
      id: t.id,
      title: t.title,
      startsAt: t.startsAt.toISOString(),
      endsAt: t.endsAt.toISOString(),
      isCurrent: t.isCurrent,
    }));
  }

  async courses(
    userId: string,
    options: { termId?: string; limit: number; cursor?: string },
  ): Promise<{ items: CourseSummary[]; nextCursor: string | null }> {
    const where: Prisma.CourseWhereInput = {
      enrollments: { some: { userId, status: 'active' } },
      status: 'published',
      ...(options.termId ? { termId: options.termId } : {}),
    };

    // Cursor pagination on a ULID primary key: ids sort by creation time, so `id > cursor` is a
    // stable page boundary even as courses are added.
    const rows = await this.prisma.course.findMany({
      where: { ...where, ...(options.cursor ? { id: { gt: options.cursor } } : {}) },
      orderBy: { id: 'asc' },
      take: options.limit + 1,
      include: {
        teacher: { select: { displayName: true } },
        _count: { select: { videos: { where: { status: 'ready' } } } },
      },
    });

    const page = rows.slice(0, options.limit);
    const items = await Promise.all(page.map((c) => this.toCourseSummary(userId, c)));

    return {
      items,
      nextCursor: rows.length > options.limit ? (page.at(-1)?.id ?? null) : null,
    };
  }

  async courseDetail(userId: string, courseId: string): Promise<CourseDetail> {
    const course = await this.prisma.course.findFirst({
      where: {
        id: courseId,
        status: 'published',
        enrollments: { some: { userId, status: 'active' } },
      },
      include: {
        teacher: { select: { displayName: true } },
        _count: { select: { videos: { where: { status: 'ready' } } } },
        sections: {
          orderBy: { order: 'asc' },
          include: {
            videos: {
              where: { status: { in: ['ready', 'processing'] } },
              orderBy: { createdAt: 'asc' },
            },
          },
        },
        videos: {
          where: { sectionId: null, status: { in: ['ready', 'processing'] } },
          orderBy: { createdAt: 'asc' },
        },
      },
    });

    // 404 rather than 403 for an unenrolled course: a 403 would confirm the course exists.
    if (!course) throw AppError.notFound('course');

    const summary = await this.toCourseSummary(userId, course);
    const progressByVideo = await this.progressMap(userId, courseId);
    const downloadedIds = await this.downloadedVideoIds(userId);

    const toSummary = (v: (typeof course.videos)[number]) =>
      this.toVideoSummary(v, progressByVideo, downloadedIds);

    return {
      ...summary,
      description: course.description,
      sections: course.sections.map((s) => ({
        id: s.id,
        title: s.title,
        order: s.order,
        videos: s.videos.map(toSummary),
      })),
      looseVideos: course.videos.map(toSummary),
    };
  }

  async videoDetail(userId: string, videoId: string): Promise<VideoDetail> {
    const video = await this.prisma.video.findFirst({
      where: {
        id: videoId,
        course: { enrollments: { some: { userId, status: 'active' } } },
      },
      include: {
        assets: { orderBy: { bitrate: 'desc' } },
        chapters: { orderBy: { startMs: 'asc' } },
        attachments: true,
      },
    });

    if (!video) throw AppError.notFound('video');

    const progressByVideo = await this.progressMap(userId, video.courseId);
    const downloadedIds = await this.downloadedVideoIds(userId);
    const summary = this.toVideoSummary(video, progressByVideo, downloadedIds);

    return {
      ...summary,
      description: video.description,
      recordedAt: video.recordedAt?.toISOString() ?? null,
      renditions: video.assets.map((a) => ({
        id: a.id,
        label: a.label,
        width: a.width,
        height: a.height,
        bitrate: a.bitrate,
        byteSize: Number(a.byteSize),
      })),
      chapters: video.chapters.map((c) => ({
        id: c.id,
        title: c.title,
        startMs: c.startMs,
      })),
      attachments: video.attachments.map((a) => ({
        id: a.id,
        name: a.name,
        mime: a.mime,
        byteSize: Number(a.byteSize),
        copyable: a.copyable,
      })),
    };
  }

  /**
   * Trigram search over normalised Persian text.
   *
   * Uses **`word_similarity` and the `<%` operator, not `similarity` and `%`**. That distinction is
   * the difference between this working and returning nothing: `similarity()` compares whole
   * strings, so a short query against a longer title scores far below the 0.3 default threshold —
   * measured at 0.14 for "مشتق" against "جلسه ۴ — مشتق توابع مرکب", i.e. no match for an obviously
   * correct one. `word_similarity(query, text)` asks whether the query matches *a word within* the
   * text, scoring 1.0 for the same pair. GIN `gin_trgm_ops` indexes support both operators.
   *
   * Raw SQL because Prisma cannot express either. Every value is parameterised — interpolating the
   * query string would be an injection hole reachable by any signed-in student.
   *
   * The enrollment join is part of the search rather than a filter applied afterwards, so an
   * unenrolled course cannot surface even as a title.
   */
  async search(
    userId: string,
    options: { q: string; courseId?: string; limit: number },
  ): Promise<{ items: SearchResult[]; nextCursor: string | null }> {
    // Normalised with the same function that generated search_text — see search.ts.
    const q = prepareSearchQuery(options.q);
    const courseFilter = options.courseId ?? null;

    const [videoHits, courseHits] = await Promise.all([
      this.prisma.$queryRaw<Array<{ id: string; score: number }>>`
        SELECT v.id, word_similarity(${q}, v.search_text) AS score
        FROM videos v
        JOIN courses c ON c.id = v.course_id
        JOIN enrollments e ON e.course_id = c.id AND e.user_id = ${userId} AND e.status = 'active'
        WHERE c.status = 'published'
          AND v.status = 'ready'
          AND (${courseFilter}::text IS NULL OR c.id = ${courseFilter}::text)
          AND ${q} <% v.search_text
        ORDER BY score DESC, v.id ASC
        LIMIT ${options.limit}
      `,
      // A course filter means "search inside this course", so course rows are not wanted.
      courseFilter
        ? Promise.resolve([])
        : this.prisma.$queryRaw<Array<{ id: string; score: number }>>`
            SELECT c.id, word_similarity(${q}, c.search_text) AS score
            FROM courses c
            JOIN enrollments e ON e.course_id = c.id AND e.user_id = ${userId} AND e.status = 'active'
            WHERE c.status = 'published'
              AND ${q} <% c.search_text
            ORDER BY score DESC, c.id ASC
            LIMIT ${options.limit}
          `,
    ]);

    const [videoRows, courseRows, progress, downloaded] = await Promise.all([
      this.prisma.video.findMany({ where: { id: { in: videoHits.map((v) => v.id) } } }),
      this.prisma.course.findMany({
        where: { id: { in: courseHits.map((c) => c.id) } },
        include: {
          teacher: { select: { displayName: true } },
          _count: { select: { videos: { where: { status: 'ready' } } } },
        },
      }),
      this.progressMap(userId),
      this.downloadedVideoIds(userId),
    ]);

    const results: SearchResult[] = [];

    for (const hit of courseHits) {
      const row = courseRows.find((c) => c.id === hit.id);
      if (row) {
        results.push({
          kind: 'course',
          course: await this.toCourseSummary(userId, row),
          score: hit.score,
        });
      }
    }

    for (const hit of videoHits) {
      const row = videoRows.find((v) => v.id === hit.id);
      if (row) {
        results.push({
          kind: 'video',
          video: this.toVideoSummary(row, progress, downloaded),
          score: hit.score,
        });
      }
    }

    results.sort((a, b) => b.score - a.score);

    return {
      items: results.slice(0, options.limit),
      // Trigram relevance ordering does not paginate stably, and a student searching their own
      // courses does not need page two. Ranked top results only, by design.
      nextCursor: null,
    };
  }

  // ── helpers ──

  private async toCourseSummary(
    userId: string,
    course: Prisma.CourseGetPayload<{
      include: {
        teacher: { select: { displayName: true } };
        _count: { select: { videos: true } };
      };
    }>,
  ): Promise<CourseSummary> {
    const videoCount = course._count.videos;
    const completed = await this.prisma.watchProgress.count({
      where: { userId, completed: true, video: { courseId: course.id } },
    });

    return {
      id: course.id,
      termId: course.termId,
      title: course.title,
      slug: course.slug,
      teacherName: course.teacher?.displayName ?? null,
      coverUrl: course.coverKey
        ? await this.storage.presignGet(this.storage.vodBucket, course.coverKey, 600)
        : null,
      videoCount,
      progress: videoCount > 0 ? completed / videoCount : 0,
      policy: {
        allowDownload: course.allowDownload,
        allowCapture: course.allowCapture,
        offlineWindowDays: course.offlineWindowDays,
        maxDevices: course.maxDevices,
        maxConcurrentStreams: course.maxConcurrentStreams,
      },
    };
  }

  private toVideoSummary(
    video: {
      id: string;
      courseId: string;
      sectionId: string | null;
      title: string;
      durationMs: number;
      status: string;
      posterKey: string | null;
      publishedAt: Date | null;
      unlockRule: Prisma.JsonValue | null;
    },
    progress: Map<string, { positionMs: number; completed: boolean }>,
    downloadedIds: Set<string>,
  ): VideoSummary {
    const p = progress.get(video.id);

    return {
      id: video.id,
      courseId: video.courseId,
      sectionId: video.sectionId,
      title: video.title,
      durationMs: video.durationMs,
      status: video.status as VideoSummary['status'],
      // A relative path rather than a presigned URL: posters are requested in bulk for a list, and
      // presigning each one would mean dozens of signature computations per page load. The client
      // fetches them through the authenticated poster endpoint instead.
      posterUrl: video.posterKey ? `/v1/catalog/videos/${video.id}/poster` : null,
      publishedAt: video.publishedAt?.toISOString() ?? null,
      progressMs: p?.positionMs ?? 0,
      completed: p?.completed ?? false,
      downloaded: downloadedIds.has(video.id),
      // M5 will evaluate unlockRule against quiz attempts. Until then nothing is gated, and saying
      // so explicitly is better than a null that might mean either.
      lockedReason: null,
    };
  }

  private async progressMap(userId: string, courseId?: string) {
    const rows = await this.prisma.watchProgress.findMany({
      where: { userId, ...(courseId ? { video: { courseId } } : {}) },
      select: { videoId: true, positionMs: true, completed: true },
    });
    return new Map(
      rows.map((r) => [r.videoId, { positionMs: r.positionMs, completed: r.completed }]),
    );
  }

  private async downloadedVideoIds(userId: string) {
    const rows = await this.prisma.download.findMany({
      where: { userId, state: 'complete' },
      select: { videoId: true },
    });
    return new Set(rows.map((r) => r.videoId));
  }
}
