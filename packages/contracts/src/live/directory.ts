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
 *   GET /v1/internal/users/:userId/courses                 → directoryUserCoursesSchema
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

/**
 * The courses someone attends or teaches: active, unexpired enrollments plus the courses they are
 * the teacher of. What "my classes" lists, so a student's dashboard shows their classes.
 */
export const directoryUserCoursesSchema = z.object({
  courseIds: z.array(id('course')),
});
export type DirectoryUserCourses = z.infer<typeof directoryUserCoursesSchema>;
