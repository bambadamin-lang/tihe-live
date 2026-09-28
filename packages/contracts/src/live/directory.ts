import { z } from 'zod';
import { id, roleSchema } from '../common.js';

/**
 * The internal API services/live calls on services/api (ADR-0012), behind its
 * `CourseDirectory` interface. Server-to-server only, authenticated with
 * `X-Internal-Token`; never exposed through nginx.
 *
 *   GET /v1/internal/courses/:courseId                     → directoryCourseSchema
 *   GET /v1/internal/enrollments/check?userId=&courseId=   → directoryEnrollmentSchema
 *   GET /v1/internal/users/:userId/profile                 → directoryProfileSchema
 */
export const directoryCourseSchema = z.object({
  id: id('course'),
  title: z.string(),
  teacherId: id('user').nullable(),
  /** Course policy: when true, capture blocking is off (accessibility, remote support). */
  allowCapture: z.boolean(),
});
export type DirectoryCourse = z.infer<typeof directoryCourseSchema>;

export const directoryEnrollmentSchema = z.object({
  enrolled: z.boolean(),
});

export const directoryProfileSchema = z.object({
  id: id('user'),
  displayName: z.string().nullable(),
  /**
   * The full number in E.164, e.g. +989121234567. Used for this user's own watermark only
   * (docs/11 §9): never logged, never sent to anyone else, never put in LiveKit metadata.
   */
  phone: z.string().regex(/^\+989\d{9}$/),
  role: roleSchema,
});
export type DirectoryProfile = z.infer<typeof directoryProfileSchema>;
