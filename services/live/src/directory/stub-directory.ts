import { readFileSync } from 'node:fs';
import {
  directoryProfileSchema,
  roleSchema,
  type DirectoryCourse,
  type DirectoryProfile,
} from '@tihe/contracts';
import { z } from 'zod';
import type { CourseDirectory } from './course-directory.js';

/**
 * Development directory: users and courses from a JSON file (services/live/dev/directory.json).
 * Phone numbers are in E.164, as the API sends them for the watermark.
 */
export const stubDirectorySchema = z.object({
  users: z.array(
    z.object({
      id: z.string(),
      displayName: z.string(),
      phone: directoryProfileSchema.shape.phone,
      role: roleSchema,
    }),
  ),
  courses: z.array(
    z.object({
      id: z.string(),
      title: z.string(),
      teacherId: z.string().nullable(),
      allowCapture: z.boolean().default(false),
      enrolled: z.array(z.string()),
    }),
  ),
});
export type StubDirectoryData = z.infer<typeof stubDirectorySchema>;

export class StubCourseDirectory implements CourseDirectory {
  constructor(private readonly data: StubDirectoryData) {}

  static fromFile(path: string): StubCourseDirectory {
    return new StubCourseDirectory(
      stubDirectorySchema.parse(JSON.parse(readFileSync(path, 'utf8'))),
    );
  }

  async course(courseId: string): Promise<DirectoryCourse | null> {
    const c = this.data.courses.find((x) => x.id === courseId);
    return c
      ? { id: c.id, title: c.title, teacherId: c.teacherId, allowCapture: c.allowCapture }
      : null;
  }

  async isEnrolled(userId: string, courseId: string): Promise<boolean> {
    return this.data.courses.find((x) => x.id === courseId)?.enrolled.includes(userId) ?? false;
  }

  async profile(userId: string): Promise<DirectoryProfile | null> {
    const u = this.data.users.find((x) => x.id === userId);
    return u ? { id: u.id, displayName: u.displayName, phone: u.phone, role: u.role } : null;
  }
}
