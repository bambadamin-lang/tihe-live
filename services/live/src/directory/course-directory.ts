import type { DirectoryCourse, DirectoryProfile } from '@tihe/contracts';

/**
 * What services/live needs to know from services/api: the course a class belongs to, whether
 * someone is enrolled, and who they are. An interface, so the classroom runs against a stub
 * before the API exists and never reads the API's tables directly (ADR-0012).
 */
export interface CourseDirectory {
  course(courseId: string): Promise<DirectoryCourse | null>;
  isEnrolled(userId: string, courseId: string): Promise<boolean>;
  profile(userId: string): Promise<DirectoryProfile | null>;
}
export const COURSE_DIRECTORY = Symbol('COURSE_DIRECTORY');
