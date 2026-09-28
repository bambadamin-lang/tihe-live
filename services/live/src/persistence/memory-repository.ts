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

/** In-memory storage for tests and for running without Postgres. Nothing survives a restart. */
export class MemoryLiveRepository implements LiveRepository {
  readonly classes = new Map<string, ClassRecord>();
  readonly sessions = new Map<string, SessionRecord & { finalSnapshot?: unknown }>();
  readonly attendance = new Map<string, AttendanceRecord>();
  readonly audit: AuditRecord[] = [];
  readonly layouts = new Map<string, LayoutRecord>();

  async createClass(record: ClassRecord) {
    this.classes.set(record.id, record);
    return record;
  }
  async updateClass(id: string, patch: Partial<ClassRecord>) {
    const next = { ...this.classes.get(id)!, ...patch };
    this.classes.set(id, next);
    return next;
  }
  async findClass(id: string) {
    return this.classes.get(id) ?? null;
  }
  async listClasses(filter: { courseId?: string; teacherId?: string }) {
    return [...this.classes.values()].filter(
      (c) =>
        (!filter.courseId || c.courseId === filter.courseId) &&
        (!filter.teacherId || c.teacherId === filter.teacherId),
    );
  }

  async createSession(record: SessionRecord) {
    this.sessions.set(record.id, record);
    return record;
  }
  async findSession(id: string) {
    return this.sessions.get(id) ?? null;
  }
  async findLiveSession(classId: string) {
    return (
      [...this.sessions.values()].find((s) => s.classId === classId && s.status === 'live') ?? null
    );
  }
  async updateSession(id: string, patch: Partial<SessionRecord> & { finalSnapshot?: unknown }) {
    const next = { ...this.sessions.get(id)!, ...patch };
    this.sessions.set(id, next);
    return next;
  }

  async recordAttendance(sessionId: string, change: AttendanceChange) {
    const key = `${sessionId}:${change.userId}`;
    this.attendance.set(key, applyAttendance(this.attendance.get(key), sessionId, change));
  }
  async listAttendance(sessionId: string) {
    return [...this.attendance.values()].filter((a) => a.sessionId === sessionId);
  }

  async appendAudit(record: AuditRecord) {
    this.audit.push(record);
  }
  async listAudit(sessionId: string) {
    return this.audit.filter((a) => a.sessionId === sessionId);
  }

  async saveLayout(record: LayoutRecord) {
    this.layouts.set(record.id, record);
    return record;
  }
  async listLayouts(ownerId: string) {
    return [...this.layouts.values()].filter((l) => l.ownerId === ownerId);
  }
  async deleteLayout(id: string, ownerId: string) {
    const found = this.layouts.get(id);
    if (!found || found.ownerId !== ownerId) return false;
    return this.layouts.delete(id);
  }
}
