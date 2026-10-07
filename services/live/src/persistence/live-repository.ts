import type { ClassRole, ClassSettings, Pod } from '@tihe/contracts';

/**
 * Storage for services/live, behind an interface so the service runs (and is tested) with an
 * in-memory implementation and uses Postgres (tihe_live) in production. Dates are UTC.
 */
export interface ClassRecord {
  id: string;
  courseId: string;
  sectionId: string | null;
  title: string;
  description: string | null;
  teacherId: string;
  scheduledStartAt: Date | null;
  durationMinutes: number;
  settings: ClassSettings;
  createdAt: Date;
}

export interface SessionRecord {
  id: string;
  classId: string;
  status: 'live' | 'ended';
  startedAt: Date;
  endedAt: Date | null;
  egressId: string | null;
  recordingStartedAt: Date | null;
  recordingEndedAt: Date | null;
  recordingError: string | null;
  peakParticipants: number;
}

export interface AttendanceRecord {
  sessionId: string;
  userId: string;
  name: string;
  role: ClassRole;
  firstJoinedAt: Date;
  lastLeftAt: Date | null;
  secondsPresent: number;
  joinCount: number;
  captureAttempts: number;
  openSince: Date | null;
}

export interface AttendanceChange {
  change: 'join' | 'leave' | 'capture';
  userId: string;
  name: string;
  role: ClassRole;
  at: Date;
}

export interface AuditRecord {
  id: string;
  sessionId: string;
  actorId: string | null;
  targetId: string | null;
  kind: string;
  detail: Record<string, unknown>;
  createdAt: Date;
}

export interface LayoutRecord {
  id: string;
  ownerId: string;
  name: string;
  pods: Pod[];
  createdAt: Date;
}

export interface LiveRepository {
  createClass(record: ClassRecord): Promise<ClassRecord>;
  updateClass(
    id: string,
    patch: Partial<Omit<ClassRecord, 'id' | 'createdAt'>>,
  ): Promise<ClassRecord>;
  findClass(id: string): Promise<ClassRecord | null>;
  /** Every filter given must match; `courseIds` matches any of them. */
  listClasses(filter: {
    courseId?: string;
    courseIds?: string[];
    teacherId?: string;
  }): Promise<ClassRecord[]>;

  createSession(record: SessionRecord): Promise<SessionRecord>;
  findSession(id: string): Promise<SessionRecord | null>;
  findLiveSession(classId: string): Promise<SessionRecord | null>;
  updateSession(
    id: string,
    patch: Partial<Omit<SessionRecord, 'id' | 'classId'>> & { finalSnapshot?: unknown },
  ): Promise<SessionRecord>;

  recordAttendance(sessionId: string, change: AttendanceChange): Promise<void>;
  listAttendance(sessionId: string): Promise<AttendanceRecord[]>;

  appendAudit(record: AuditRecord): Promise<void>;
  listAudit(sessionId: string): Promise<AuditRecord[]>;

  saveLayout(record: LayoutRecord): Promise<LayoutRecord>;
  listLayouts(ownerId: string): Promise<LayoutRecord[]>;
  deleteLayout(id: string, ownerId: string): Promise<boolean>;
}
export const LIVE_REPOSITORY = Symbol('LIVE_REPOSITORY');

/**
 * The attendance arithmetic, shared by both implementations: time is summed across reconnects,
 * so a flaky connection neither inflates nor erases someone's presence.
 */
export function applyAttendance(
  existing: AttendanceRecord | undefined,
  sessionId: string,
  c: AttendanceChange,
): AttendanceRecord {
  const row: AttendanceRecord = existing
    ? { ...existing, name: c.name, role: c.role }
    : {
        sessionId,
        userId: c.userId,
        name: c.name,
        role: c.role,
        firstJoinedAt: c.at,
        lastLeftAt: null,
        secondsPresent: 0,
        joinCount: 0,
        captureAttempts: 0,
        openSince: null,
      };
  switch (c.change) {
    case 'join':
      row.joinCount += 1;
      row.openSince ??= c.at;
      break;
    case 'leave':
      if (row.openSince) {
        row.secondsPresent += Math.max(
          0,
          Math.round((c.at.getTime() - row.openSince.getTime()) / 1000),
        );
      }
      row.openSince = null;
      row.lastLeftAt = c.at;
      break;
    case 'capture':
      row.captureAttempts += 1;
      break;
  }
  return row;
}
