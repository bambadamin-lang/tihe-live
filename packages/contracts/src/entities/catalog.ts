import { z } from 'zod';
import { id } from '../common.js';

export const termSchema = z.object({
  id: id('term'),
  title: z.string(),
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime(),
  isCurrent: z.boolean(),
});
export type Term = z.infer<typeof termSchema>;

/**
 * Protection policy lives on the course, not the video, so an admin changes it in one place
 * and every video in the course inherits it.
 */
export const coursePolicySchema = z.object({
  allowDownload: z.boolean(),
  /**
   * When false, the player blocks screen capture (Android FLAG_SECURE / Windows
   * WDA_EXCLUDEFROMCAPTURE). Exposed per course because capture blocking also breaks
   * legitimate accessibility and remote-support tools.
   */
  allowCapture: z.boolean(),
  offlineWindowDays: z.number().int().positive(),
  maxDevices: z.number().int().positive(),
  maxConcurrentStreams: z.number().int().positive(),
});
export type CoursePolicy = z.infer<typeof coursePolicySchema>;

export const courseSummarySchema = z.object({
  id: id('course'),
  termId: id('term').nullable(),
  title: z.string(),
  slug: z.string(),
  teacherName: z.string().nullable(),
  coverUrl: z.string().url().nullable(),
  videoCount: z.number().int().nonnegative(),
  /** 0–1. Fraction of videos the student has completed, for the progress ring. */
  progress: z.number().min(0).max(1),
  policy: coursePolicySchema,
});
export type CourseSummary = z.infer<typeof courseSummarySchema>;

export const videoStatusSchema = z.enum(['processing', 'pending_review', 'ready', 'failed']);
export type VideoStatus = z.infer<typeof videoStatusSchema>;

export const renditionSchema = z.object({
  id: z.string(),
  label: z.string(), // "1080p", "audio"
  width: z.number().int().nullable(),
  height: z.number().int().nullable(),
  bitrate: z.number().int(),
  byteSize: z.number().int(),
});
export type Rendition = z.infer<typeof renditionSchema>;

export const chapterSchema = z.object({
  id: id('chapter'),
  title: z.string(),
  startMs: z.number().int().nonnegative(),
});
export type Chapter = z.infer<typeof chapterSchema>;

export const attachmentSchema = z.object({
  id: id('attachment'),
  name: z.string(),
  mime: z.string(),
  byteSize: z.number().int(),
  /** False means it renders in-app but cannot be exported — SpotPlayer's protected-file mode. */
  copyable: z.boolean(),
});
export type Attachment = z.infer<typeof attachmentSchema>;

export const videoSummarySchema = z.object({
  id: id('video'),
  courseId: id('course'),
  sectionId: id('section').nullable(),
  title: z.string(),
  durationMs: z.number().int().nonnegative(),
  status: videoStatusSchema,
  posterUrl: z.string().url().nullable(),
  publishedAt: z.string().datetime().nullable(),
  /** Resume point, so a list can show a progress bar without a second request. */
  progressMs: z.number().int().nonnegative(),
  completed: z.boolean(),
  /** Whether this device already holds it offline. */
  downloaded: z.boolean(),
  /** Set when a quiz or prerequisite gates this video (M5). */
  lockedReason: z.string().nullable(),
});
export type VideoSummary = z.infer<typeof videoSummarySchema>;

export const videoDetailSchema = videoSummarySchema.extend({
  description: z.string().nullable(),
  renditions: z.array(renditionSchema),
  chapters: z.array(chapterSchema),
  attachments: z.array(attachmentSchema),
  /** Present when the video came from a live class, so the UI can show the class date. */
  recordedAt: z.string().datetime().nullable(),
});
export type VideoDetail = z.infer<typeof videoDetailSchema>;

export const courseSectionSchema = z.object({
  id: id('section'),
  title: z.string(),
  order: z.number().int(),
  videos: z.array(videoSummarySchema),
});
export type CourseSection = z.infer<typeof courseSectionSchema>;

export const courseDetailSchema = courseSummarySchema.extend({
  description: z.string().nullable(),
  sections: z.array(courseSectionSchema),
  /** Videos not filed under any section. */
  looseVideos: z.array(videoSummarySchema),
});
export type CourseDetail = z.infer<typeof courseDetailSchema>;
