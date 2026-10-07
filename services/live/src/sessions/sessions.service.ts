import { randomInt } from 'node:crypto';
import { Inject, Injectable, Logger } from '@nestjs/common';
import {
  DEFAULT_RECORDER_PROCESSES,
  LAYOUT_PRESETS,
  ROLE_RANK,
  liveWatermarkText,
  watermarkShortId,
  type AttendanceEntry,
  type ClassRole,
  type JoinResponse,
  type LiveSession,
} from '@tihe/contracts';
import type { Caller } from '../auth/access-token.js';
import { TicketService } from '../auth/tickets.js';
import { ClassAccess } from '../classes/access.js';
import { ClassesService } from '../classes/classes.service.js';
import { CLOCK, ClassroomHub, type Clock } from '../classroom/classroom-hub.js';
import type { RoomActor } from '../classroom/room-actor.js';
import { LIVE_CONFIG, type LiveConfig } from '../config.js';
import { effectiveCapabilities, mediaSources } from '../core/capabilities.js';
import { newId } from '../core/ids.js';
import { COURSE_DIRECTORY, type CourseDirectory } from '../directory/course-directory.js';
import { LiveHttpError } from '../http/errors.js';
import { LIVEKIT_PORT, type LiveKitPort } from '../livekit/livekit.port.js';
import {
  LIVE_REPOSITORY,
  type ClassRecord,
  type LiveRepository,
  type SessionRecord,
} from '../persistence/live-repository.js';
import { RecordingService } from '../recording/recording.service.js';

/** Room headroom over the class limit: the recorder, and a host rejoining from a second device. */
const ROOM_HEADROOM = 3;

/** Long enough to close a recorder that opened by accident; too short to record a lesson. */
const RECORDING_GRACE_SECONDS = 10;

@Injectable()
export class SessionsService {
  private readonly logger = new Logger('SessionsService');

  constructor(
    @Inject(LIVE_REPOSITORY) private readonly repo: LiveRepository,
    @Inject(LIVEKIT_PORT) private readonly livekit: LiveKitPort,
    @Inject(COURSE_DIRECTORY) private readonly directory: CourseDirectory,
    @Inject(LIVE_CONFIG) private readonly config: LiveConfig,
    @Inject(CLOCK) private readonly clock: Clock,
    @Inject(TicketService) private readonly tickets: TicketService,
    private readonly hub: ClassroomHub,
    private readonly classes: ClassesService,
    private readonly access: ClassAccess,
    private readonly recording: RecordingService,
  ) {}

  /** The host starts the class. Idempotent: a second call returns the session already live. */
  async start(caller: Caller, classId: string): Promise<LiveSession> {
    const liveClass = await this.classes.load(caller, classId, 'host');
    const existing = await this.repo.findLiveSession(classId);
    if (existing) return this.toDto(existing);

    const session = await this.repo.createSession({
      id: newId('liveSession'),
      classId,
      status: 'live',
      startedAt: this.clock(),
      endedAt: null,
      egressId: null,
      recordingStartedAt: null,
      recordingEndedAt: null,
      recordingError: null,
      peakParticipants: 0,
    });
    await this.livekit.createRoom({
      name: session.id,
      maxParticipants: liveClass.settings.maxParticipants + ROOM_HEADROOM,
      metadata: JSON.stringify({ classId }),
    });
    await this.openRoom(liveClass, session);

    const current = liveClass.settings.autoRecord
      ? await this.recording.start(liveClass, session)
      : session;
    return this.toDto(current);
  }

  async get(caller: Caller, sessionId: string): Promise<LiveSession> {
    const { session } = await this.load(caller, sessionId);
    return this.toDto(session);
  }

  /**
   * Everything a client needs to enter: a LiveKit token with exactly its current publish rights,
   * a gateway ticket, its own watermark, and the capture policy.
   */
  async join(caller: Caller, sessionId: string): Promise<JoinResponse> {
    const { liveClass, session, role: accessRole } = await this.load(caller, sessionId);
    if (session.status !== 'live') throw new LiveHttpError('CLASS_ENDED', 'this session has ended');
    const actor = (await this.hub.find(sessionId)) ?? (await this.openRoom(liveClass, session));
    const state = actor.state;

    if (state.removed.has(caller.userId)) {
      throw new LiveHttpError('REMOVED_FROM_CLASS', 'removed from this session');
    }
    const existing = state.participants.get(caller.userId);
    // A rejoin keeps the role the class gave them (a promotion survives a dropped connection).
    const role: ClassRole = existing?.role ?? accessRole;
    const privileged = ROLE_RANK[role] >= ROLE_RANK.cohost;
    if (state.policy.locked && !existing && !privileged) {
      throw new LiveHttpError('CLASS_LOCKED', 'the host locked this class');
    }
    if (
      !existing?.online &&
      !privileged &&
      actor.onlineCount >= liveClass.settings.maxParticipants
    ) {
      throw new LiveHttpError('CLASS_FULL', 'the class is full');
    }

    const [profile, course] = await Promise.all([
      this.directory.profile(caller.userId),
      this.directory.course(liveClass.courseId),
    ]);
    const name = profile?.displayName ?? `کاربر ${watermarkShortId(caller.userId)}`;
    const caps = existing?.caps ?? effectiveCapabilities(role, state.policy, [], []);

    const [token, { ticket, expiresAt }] = await Promise.all([
      this.livekit.mintToken({
        room: sessionId,
        identity: caller.userId,
        name,
        sources: mediaSources(caps),
        // Public to everyone in the room: role only. Never the phone number.
        metadata: JSON.stringify({ role }),
      }),
      this.tickets.mint({ sessionId, userId: caller.userId, name, role }, this.clock()),
    ]);

    const captureAllowed = course?.allowCapture ?? false;
    return {
      session: this.toDto(session),
      classTitle: liveClass.title,
      you: { userId: caller.userId, name, role },
      livekit: { url: this.config.LIVEKIT_URL, token },
      gateway: {
        url: this.config.PUBLIC_GATEWAY_URL,
        ticket,
        ticketExpiresAt: expiresAt.toISOString(),
      },
      watermark: {
        text: profile
          ? liveWatermarkText(profile.phoneMasked, caller.userId)
          : `#${watermarkShortId(caller.userId)}`,
        opacity: 0.32,
        fontSize: 13,
        movement: 'corners',
        // A different rhythm and path per join, so the corner sequence cannot be predicted
        // and cropped around in a long recording.
        periodSeconds: randomInt(25, 46),
        seed: randomInt(0, 2 ** 31 - 1),
      },
      capturePolicy: {
        block: !captureAllowed,
        // Students: a visible black box. Presenters: vanish from captures, so their own screen
        // share does not contain a black hole (ADR-0011).
        windowsAffinity: ROLE_RANK[role] >= ROLE_RANK.presenter ? 'exclude' : 'monitor',
        censorAudio: true,
        reportToHost: true,
        recorderProcesses: DEFAULT_RECORDER_PROCESSES,
        iosSecureLayer: this.config.IOS_SECURE_LAYER,
        scanIntervalMs: 3000,
        recordingGraceSeconds: captureAllowed ? null : RECORDING_GRACE_SECONDS,
      },
    };
  }

  /** Only the one-time start; there is no stop short of ending the class (docs/11 §10). */
  async startRecording(caller: Caller, sessionId: string): Promise<LiveSession> {
    const { liveClass, session } = await this.load(caller, sessionId, 'recording.control');
    if (session.status !== 'live') throw new LiveHttpError('CLASS_ENDED', 'this session has ended');
    return this.toDto(await this.recording.start(liveClass, session));
  }

  async end(caller: Caller, sessionId: string): Promise<LiveSession> {
    const { liveClass, session } = await this.load(caller, sessionId, 'class.end');
    return this.toDto(await this.finish(liveClass, session, 'host_ended'));
  }

  /** LiveKit closed the room on its own (everyone left long ago). */
  async endAbandoned(sessionId: string): Promise<void> {
    const session = await this.repo.findSession(sessionId);
    if (!session || session.status !== 'live') return;
    const liveClass = await this.repo.findClass(session.classId);
    if (liveClass) await this.finish(liveClass, session, 'timeout');
  }

  async attendance(caller: Caller, sessionId: string): Promise<AttendanceEntry[]> {
    await this.load(caller, sessionId, 'participants.manage');
    const rows = await this.repo.listAttendance(sessionId);
    return rows.map((a) => ({
      userId: a.userId,
      name: a.name,
      role: a.role,
      firstJoinedAt: a.firstJoinedAt.toISOString(),
      lastLeftAt: a.lastLeftAt?.toISOString() ?? null,
      secondsPresent: a.secondsPresent,
      captureAttempts: a.captureAttempts,
    }));
  }

  /**
   * The order matters: tell the room, stop the recording with its final metadata, close out
   * attendance, then disconnect everyone and close the LiveKit room.
   */
  private async finish(
    liveClass: ClassRecord,
    session: SessionRecord,
    reason: 'host_ended' | 'timeout',
  ): Promise<SessionRecord> {
    if (session.status === 'ended') return session;
    const actor = await this.hub.find(session.id);
    const now = this.clock();

    const online = actor ? [...actor.state.participants.values()].filter((p) => p.online) : [];
    const attendees = actor ? actor.state.participants.size : 0;
    actor?.submit({ kind: 'end', reason });

    await this.recording.stop(liveClass, session, attendees).catch((err) => {
      this.logger.error(`stopping recording for ${session.id} failed`, err);
    });
    for (const p of online) {
      await this.repo.recordAttendance(session.id, {
        change: 'leave',
        userId: p.userId,
        name: p.name,
        role: p.role,
        at: now,
      });
    }
    const peak = this.hub.peak(session.id);
    const final = await this.hub.close(session.id);
    await this.livekit.deleteRoom(session.id).catch((err) => {
      this.logger.error(`closing LiveKit room ${session.id} failed`, err);
    });
    return this.repo.updateSession(session.id, {
      status: 'ended',
      endedAt: now,
      peakParticipants: Math.max(peak, session.peakParticipants),
      ...(final && { finalSnapshot: final }),
    });
  }

  private async openRoom(liveClass: ClassRecord, session: SessionRecord): Promise<RoomActor> {
    return this.hub.open({
      sessionId: session.id,
      classId: liveClass.id,
      title: liveClass.title,
      startedAt: session.startedAt.toISOString(),
      policy: liveClass.settings.policy,
      layout: LAYOUT_PRESETS[liveClass.settings.defaultLayout],
      firstPageId: newId('boardPage'),
    });
  }

  /**
   * The session and the caller's standing in it. With `cap`, the caller must hold that
   * capability in the running room — or host the class by account, so a teacher whose
   * connection dropped can still end their own class.
   */
  private async load(
    caller: Caller,
    sessionId: string,
    cap?: 'recording.control' | 'class.end' | 'participants.manage',
  ): Promise<{ liveClass: ClassRecord; session: SessionRecord; role: 'host' | 'participant' }> {
    const session = await this.repo.findSession(sessionId);
    const liveClass = session ? await this.repo.findClass(session.classId) : null;
    const role = liveClass ? await this.access.roleIn(caller, liveClass) : null;
    if (!session || !liveClass || !role) throw new LiveHttpError('NOT_FOUND', 'no such session');
    if (cap && role !== 'host') {
      const inRoom = (await this.hub.find(sessionId))?.state.participants.get(caller.userId);
      if (!inRoom?.caps.includes(cap))
        throw new LiveHttpError('CAPABILITY_MISSING', `missing ${cap}`);
    }
    return { liveClass, session, role };
  }

  toDto(s: SessionRecord): LiveSession {
    const active = Boolean(s.egressId && s.recordingStartedAt && !s.recordingEndedAt);
    return {
      id: s.id,
      classId: s.classId,
      status: s.status,
      startedAt: s.startedAt.toISOString(),
      endedAt: s.endedAt?.toISOString() ?? null,
      recording: {
        active,
        startedAt: active ? (s.recordingStartedAt?.toISOString() ?? null) : null,
      },
    };
  }
}
