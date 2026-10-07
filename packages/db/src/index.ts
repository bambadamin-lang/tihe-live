/**
 * @tihe/db — the database layer, shared by the API and the workers.
 *
 * The schema lives here rather than inside `services/api` because it is not the API's alone:
 * `media-worker` writes `video_assets` and `content_keys`, and `ingest-worker` writes `recordings`.
 * The alternatives were a second copy of the schema (which drifts) or a worker importing the whole
 * NestJS dependency graph to reach the client.
 *
 * Migrations and the seed live alongside the schema in `prisma/`, so the thing that defines the
 * database and the thing that migrates it cannot get separated.
 */
export { PrismaClient, Prisma } from '@prisma/client';

export type {
  User,
  Device,
  LoginAttempt,
  Setting,
  RefreshToken,
  Term,
  Course,
  CourseSection,
  Enrollment,
  Video,
  VideoAsset,
  ContentKey,
  Recording,
  License,
  LicenseDevice,
  Download,
  PlaybackSession,
  WatchProgress,
  WatchEvent,
  Chapter,
  Attachment,
  Note,
  Quiz,
  QuizQuestion,
  QuizAttempt,
  Role,
  UserStatus,
  Platform,
  CourseStatus,
  EnrollmentStatus,
  VideoSource,
  VideoStatus,
  RecordingStatus,
  DownloadState,
  WatchEventKind,
} from '@prisma/client';

export { newId, ID_PREFIXES, type IdKind } from './ids.js';
