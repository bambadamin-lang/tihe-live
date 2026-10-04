import { Inject, Injectable } from '@nestjs/common';
import {
  DEFAULT_LAYOUT_PRESET,
  DEFAULT_ROOM_POLICY,
  type ClassSettings,
  type CreateClassBody,
  type LiveClass,
  type UpdateClassBody,
} from '@tihe/contracts';
import type { Caller } from '../auth/access-token.js';
import { CLOCK, type Clock } from '../classroom/classroom-hub.js';
import { newId } from '../core/ids.js';
import { COURSE_DIRECTORY, type CourseDirectory } from '../directory/course-directory.js';
import { LiveHttpError } from '../http/errors.js';
import {
  LIVE_REPOSITORY,
  type ClassRecord,
  type LiveRepository,
} from '../persistence/live-repository.js';
import { ClassAccess } from './access.js';

export const DEFAULT_CLASS_SETTINGS: ClassSettings = {
  autoRecord: true,
  defaultLayout: DEFAULT_LAYOUT_PRESET,
  policy: DEFAULT_ROOM_POLICY,
  maxParticipants: 100,
};

@Injectable()
export class ClassesService {
  constructor(
    @Inject(LIVE_REPOSITORY) private readonly repo: LiveRepository,
    @Inject(COURSE_DIRECTORY) private readonly directory: CourseDirectory,
    @Inject(CLOCK) private readonly clock: Clock,
    private readonly access: ClassAccess,
  ) {}

  async create(caller: Caller, body: CreateClassBody): Promise<LiveClass> {
    const course = await this.directory.course(body.courseId);
    if (!course) throw new LiveHttpError('NOT_FOUND', 'no such course');
    if (!(await this.access.canHostCourse(caller, body.courseId))) {
      throw new LiveHttpError(
        'FORBIDDEN',
        'only the course teacher or an admin can create a class',
      );
    }
    const record = await this.repo.createClass({
      id: newId('liveClass'),
      courseId: body.courseId,
      sectionId: body.sectionId ?? null,
      title: body.title,
      description: body.description ?? null,
      teacherId: course.teacherId ?? caller.userId,
      scheduledStartAt: body.scheduledStartAt ? new Date(body.scheduledStartAt) : null,
      durationMinutes: body.durationMinutes,
      settings: mergeSettings(DEFAULT_CLASS_SETTINGS, body.settings),
      createdAt: this.clock(),
    });
    return this.toDto(record);
  }

  async list(caller: Caller, courseId: string | undefined): Promise<LiveClass[]> {
    let records: ClassRecord[];
    if (courseId) {
      const allowed =
        (await this.access.canHostCourse(caller, courseId)) ||
        (await this.directory.isEnrolled(caller.userId, courseId));
      if (!allowed) throw new LiveHttpError('NOT_ENROLLED', 'not enrolled in this course');
      records = await this.repo.listClasses({ courseId });
    } else if (caller.accountRole === 'admin') {
      // Admins host every class, so they see every class.
      records = await this.repo.listClasses({});
    } else {
      // Without a course, "my classes": the ones I teach and those of every course I attend or
      // teach, which is what a student's dashboard lists.
      const [taught, ofMyCourses] = await Promise.all([
        this.repo.listClasses({ teacherId: caller.userId }),
        this.directory
          .coursesOf(caller.userId)
          .then((courseIds) =>
            courseIds.length ? this.repo.listClasses({ courseIds }) : Promise.resolve([]),
          ),
      ]);
      records = [...new Map([...taught, ...ofMyCourses].map((r) => [r.id, r])).values()];
    }
    return Promise.all(records.map((r) => this.toDto(r)));
  }

  async get(caller: Caller, id: string): Promise<LiveClass> {
    const record = await this.load(caller, id);
    return this.toDto(record);
  }

  async update(caller: Caller, id: string, body: UpdateClassBody): Promise<LiveClass> {
    const record = await this.load(caller, id, 'host');
    const next = await this.repo.updateClass(id, {
      ...(body.title !== undefined && { title: body.title }),
      ...(body.description !== undefined && { description: body.description }),
      ...(body.sectionId !== undefined && { sectionId: body.sectionId }),
      ...(body.durationMinutes !== undefined && { durationMinutes: body.durationMinutes }),
      ...(body.scheduledStartAt !== undefined && {
        scheduledStartAt: new Date(body.scheduledStartAt),
      }),
      ...(body.settings && { settings: mergeSettings(record.settings, body.settings) }),
    });
    return this.toDto(next);
  }

  /** The class, if the caller may see it (or host it, when `need` is 'host'). 404 otherwise. */
  async load(caller: Caller, id: string, need?: 'host'): Promise<ClassRecord> {
    const record = await this.repo.findClass(id);
    const role = record ? await this.access.roleIn(caller, record) : null;
    // Unenrolled callers get the same 404 as a missing class: classes are not a discovery surface.
    if (!record || !role) throw new LiveHttpError('NOT_FOUND', 'no such class');
    if (need === 'host' && role !== 'host') throw new LiveHttpError('FORBIDDEN', 'hosts only');
    return record;
  }

  async toDto(r: ClassRecord): Promise<LiveClass> {
    const live = await this.repo.findLiveSession(r.id);
    return {
      id: r.id,
      courseId: r.courseId,
      sectionId: r.sectionId,
      title: r.title,
      description: r.description,
      teacherId: r.teacherId,
      scheduledStartAt: r.scheduledStartAt?.toISOString() ?? null,
      durationMinutes: r.durationMinutes,
      settings: r.settings,
      liveSessionId: live?.id ?? null,
      createdAt: r.createdAt.toISOString(),
    };
  }
}

function mergeSettings(
  base: ClassSettings,
  patch: Partial<ClassSettings> | undefined,
): ClassSettings {
  if (!patch) return base;
  return { ...base, ...patch, policy: { ...base.policy, ...patch.policy } };
}
