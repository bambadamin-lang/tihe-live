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
  /** Masked, e.g. 0912•••6789. Used for this user's own watermark only. */
  phoneMasked: z.string(),
  role: roleSchema,
});
export type DirectoryProfile = z.infer<typeof directoryProfileSchema>;
