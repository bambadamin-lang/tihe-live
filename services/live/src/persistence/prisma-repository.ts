import { PrismaPg } from '@prisma/adapter-pg';
import { classSettingsSchema, podSchema, type ClassRole } from '@tihe/contracts';
import { z } from 'zod';
import { PrismaClient, type Prisma } from '../generated/prisma/client.js';
import {
  applyAttendance,
  type AttendanceChange,
  type AttendanceRecord,
  type AuditRecord,
  type ClassRecord,
  type LayoutRecord,
  type LiveRepository,
  type SessionRecord,
} from './live-repository.js';

type ClassRow = Prisma.LiveClassGetPayload<object>;
type SessionRow = Prisma.LiveSessionGetPayload<object>;
type AttendanceRow = Prisma.LiveAttendanceGetPayload<object>;

const toClass = (r: ClassRow): ClassRecord => ({
  id: r.id,
  courseId: r.courseId,
  sectionId: r.sectionId,
  title: r.title,
  description: r.description,
  teacherId: r.teacherId,
  scheduledStartAt: r.scheduledStartAt,
  durationMinutes: r.durationMinutes,
  // JSON columns are re-validated on the way out: a bad row fails here, not in a classroom.
  settings: classSettingsSchema.parse(r.settings),
  createdAt: r.createdAt,
});

const toSession = (r: SessionRow): SessionRecord => ({
  id: r.id,
  classId: r.classId,
  status: r.status === 'ended' ? 'ended' : 'live',
  startedAt: r.startedAt,
  endedAt: r.endedAt,
  egressId: r.egressId,
  recordingStartedAt: r.recordingStartedAt,
  recordingEndedAt: r.recordingEndedAt,
  recordingError: r.recordingError,
  peakParticipants: r.peakParticipants,
});

const toAttendance = (r: AttendanceRow): AttendanceRecord => ({ ...r, role: r.role as ClassRole });

/** Postgres storage in the tihe_live database (ADR-0012). */
export class PrismaLiveRepository implements LiveRepository {
  readonly prisma: PrismaClient;

  constructor(connectionString: string) {
    this.prisma = new PrismaClient({ adapter: new PrismaPg({ connectionString }) });
  }

  async createClass(record: ClassRecord) {
    return toClass(
      await this.prisma.liveClass.create({ data: { ...record, settings: record.settings } }),
    );
  }
  async updateClass(id: string, patch: Partial<Omit<ClassRecord, 'id' | 'createdAt'>>) {
    return toClass(await this.prisma.liveClass.update({ where: { id }, data: patch }));
  }
  async findClass(id: string) {
    const row = await this.prisma.liveClass.findUnique({ where: { id } });
    return row ? toClass(row) : null;
  }
  async listClasses(filter: { courseId?: string; teacherId?: string }) {
    const rows = await this.prisma.liveClass.findMany({
      where: { courseId: filter.courseId, teacherId: filter.teacherId },
      orderBy: [{ scheduledStartAt: 'asc' }, { createdAt: 'asc' }],
    });
    return rows.map(toClass);
  }

  async createSession(record: SessionRecord) {
    return toSession(await this.prisma.liveSession.create({ data: record }));
  }
  async findSession(id: string) {
    const row = await this.prisma.liveSession.findUnique({ where: { id } });
    return row ? toSession(row) : null;
  }
  async findLiveSession(classId: string) {
    const row = await this.prisma.liveSession.findFirst({ where: { classId, status: 'live' } });
    return row ? toSession(row) : null;
  }
  async updateSession(
    id: string,
    patch: Partial<Omit<SessionRecord, 'id' | 'classId'>> & { finalSnapshot?: unknown },
  ) {
    const { finalSnapshot, ...rest } = patch;
    const data: Prisma.LiveSessionUpdateInput = { ...rest };
    if (finalSnapshot !== undefined) data.finalSnapshot = finalSnapshot as Prisma.InputJsonValue;
    return toSession(await this.prisma.liveSession.update({ where: { id }, data }));
  }

  async recordAttendance(sessionId: string, change: AttendanceChange) {
    await this.prisma.$transaction(async (tx) => {
      const key = { sessionId_userId: { sessionId, userId: change.userId } };
      const existing = await tx.liveAttendance.findUnique({ where: key });
      const row = applyAttendance(existing ? toAttendance(existing) : undefined, sessionId, change);
      await tx.liveAttendance.upsert({ where: key, create: row, update: row });
    });
  }
  async listAttendance(sessionId: string) {
    const rows = await this.prisma.liveAttendance.findMany({
      where: { sessionId },
      orderBy: { firstJoinedAt: 'asc' },
    });
    return rows.map(toAttendance);
  }

  async appendAudit(record: AuditRecord) {
    await this.prisma.liveAuditEvent.create({
      data: { ...record, detail: record.detail as Prisma.InputJsonValue },
    });
  }
  async listAudit(sessionId: string) {
    const rows = await this.prisma.liveAuditEvent.findMany({
      where: { sessionId },
      orderBy: { createdAt: 'asc' },
    });
    return rows.map((r) => ({ ...r, detail: r.detail as Record<string, unknown> }));
  }

  async saveLayout(record: LayoutRecord) {
    await this.prisma.savedLayout.create({
      data: { ...record, pods: record.pods as unknown as Prisma.InputJsonValue },
    });
    return record;
  }
  async listLayouts(ownerId: string) {
    const rows = await this.prisma.savedLayout.findMany({
      where: { ownerId },
      orderBy: { createdAt: 'asc' },
    });
    return rows.map((r) => ({ ...r, pods: z.array(podSchema).parse(r.pods) }));
  }
  async deleteLayout(id: string, ownerId: string) {
    const { count } = await this.prisma.savedLayout.deleteMany({ where: { id, ownerId } });
    return count > 0;
  }
}
