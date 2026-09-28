import {
  directoryCourseSchema,
  directoryEnrollmentSchema,
  directoryProfileSchema,
  type DirectoryCourse,
  type DirectoryProfile,
} from '@tihe/contracts';
import type { ZodTypeAny, z } from 'zod';
import type { CourseDirectory } from './course-directory.js';

/**
 * The production directory: services/api's internal endpoints (contract in
 * packages/contracts/src/live/directory.ts). A 404 means "no such thing"; anything else that is
 * not a 200 is an outage and throws, so a join fails loudly rather than admitting or refusing
 * someone on bad data.
 */
export class HttpCourseDirectory implements CourseDirectory {
  constructor(
    private readonly baseUrl: string,
    private readonly token: string,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  private async get<S extends ZodTypeAny>(path: string, schema: S): Promise<z.infer<S> | null> {
    const res = await this.fetchImpl(`${this.baseUrl}${path}`, {
      headers: { 'x-internal-token': this.token, accept: 'application/json' },
      signal: AbortSignal.timeout(5000),
    });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`directory ${path.split('?')[0]} answered ${res.status}`);
    return schema.parse(await res.json());
  }

  course(courseId: string): Promise<DirectoryCourse | null> {
    return this.get(`/v1/internal/courses/${encodeURIComponent(courseId)}`, directoryCourseSchema);
  }

  async isEnrolled(userId: string, courseId: string): Promise<boolean> {
    const q = new URLSearchParams({ userId, courseId });
    const res = await this.get(`/v1/internal/enrollments/check?${q}`, directoryEnrollmentSchema);
    return res?.enrolled ?? false;
  }

  profile(userId: string): Promise<DirectoryProfile | null> {
    return this.get(
      `/v1/internal/users/${encodeURIComponent(userId)}/profile`,
      directoryProfileSchema,
    );
  }
}
