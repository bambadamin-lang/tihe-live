import { Inject, Injectable } from '@nestjs/common';
import type { Caller } from '../auth/access-token.js';
import { COURSE_DIRECTORY, type CourseDirectory } from '../directory/course-directory.js';
import type { ClassRecord } from '../persistence/live-repository.js';

/**
 * Who someone is to a class, decided from services/api's data: its teacher and admins host it,
 * enrolled students attend it, everyone else is refused. A role *inside* a running class can
 * change later (a promotion); that lives in the room, not here.
 */
@Injectable()
export class ClassAccess {
  constructor(@Inject(COURSE_DIRECTORY) private readonly directory: CourseDirectory) {}

  async canHostCourse(caller: Caller, courseId: string): Promise<boolean> {
    if (caller.accountRole === 'admin') return true;
    const course = await this.directory.course(courseId);
    return course?.teacherId === caller.userId;
  }

  async roleIn(caller: Caller, liveClass: ClassRecord): Promise<'host' | 'participant' | null> {
    if (caller.accountRole === 'admin' || liveClass.teacherId === caller.userId) return 'host';
    if (await this.canHostCourse(caller, liveClass.courseId)) return 'host';
    if (await this.directory.isEnrolled(caller.userId, liveClass.courseId)) return 'participant';
    return null;
  }
}
