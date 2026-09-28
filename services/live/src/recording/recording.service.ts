import { Inject, Injectable, Logger } from '@nestjs/common';
import { recordingMetadataSchema, type RecordingMetadata } from '@tihe/contracts';
import { CLOCK, ClassroomHub, type Clock } from '../classroom/classroom-hub.js';
import { LIVE_CONFIG, type LiveConfig } from '../config.js';
import { newId } from '../core/ids.js';
import { LIVEKIT_PORT, type LiveKitPort } from '../livekit/livekit.port.js';
import {
  LIVE_REPOSITORY,
  type ClassRecord,
  type LiveRepository,
  type SessionRecord,
} from '../persistence/live-repository.js';
import { OBJECT_STORE, type ObjectStore } from '../storage/object-store.js';

/**
 * Server-side recording — the only kind there is (docs/11 §10). Owns the live→VOD handoff on
 * this side of the contract in docs/06: the raw path, `metadata.json`, and the ordering that
 * keeps ingest from ever reading a stale copy.
 */
@Injectable()
export class RecordingService {
  private readonly logger = new Logger('RecordingService');

  constructor(
    @Inject(LIVEKIT_PORT) private readonly livekit: LiveKitPort,
    @Inject(OBJECT_STORE) private readonly objects: ObjectStore,
    @Inject(LIVE_REPOSITORY) private readonly repo: LiveRepository,
    @Inject(LIVE_CONFIG) private readonly config: LiveConfig,
    @Inject(CLOCK) private readonly clock: Clock,
    private readonly hub: ClassroomHub,
  ) {}

  static prefix(classId: string, sessionId: string): string {
    return `recordings/${classId}/${sessionId}`;
  }

  /**
   * Starts the one egress a session gets. Egress cannot pause, and a second egress would
   * overwrite composite.mp4, so this is idempotent rather than restartable.
   */
  async start(liveClass: ClassRecord, session: SessionRecord): Promise<SessionRecord> {
    if (session.egressId) return session;
    const prefix = RecordingService.prefix(liveClass.id, session.id);

    // metadata.json first: docs/06 requires it to exist no later than egress start, and
    // courseId in it is what lets ingest publish to the right audience.
    await this.writeMetadata(liveClass, session, {
      egressIds: [],
      actualEndAt: null,
      participantCount: null,
    });

    const templateUrl = `${this.config.EGRESS_TEMPLATE_URL}?${new URLSearchParams({
      session: session.id,
      gateway: this.config.EGRESS_GATEWAY_URL,
    })}`;
    let egressId: string;
    try {
      egressId = await this.livekit.startRecording({
        room: session.id,
        filepath: `${prefix}/composite.mp4`,
        templateUrl,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.logger.error(`recording ${session.id} failed to start: ${message}`);
      await this.repo.appendAudit({
        id: newId('liveAudit'),
        sessionId: session.id,
        actorId: null,
        targetId: null,
        kind: 'recording.failed',
        detail: { message },
        createdAt: this.clock(),
      });
      return this.repo.updateSession(session.id, { recordingError: message });
    }

    const startedAt = this.clock();
    const next = await this.repo.updateSession(session.id, {
      egressId,
      recordingStartedAt: startedAt,
    });
    await this.writeMetadata(liveClass, next, {
      egressIds: [egressId],
      actualEndAt: null,
      participantCount: null,
    });
    (await this.hub.find(session.id))?.submit({
      kind: 'recording',
      recording: { active: true, startedAt: startedAt.toISOString() },
    });
    return next;
  }

  /**
   * Final metadata.json **before** stopEgress: by the time LiveKit fires egress_ended and the
   * pipeline reads the file, it already carries the end time and attendance (docs/06).
   */
  async stop(
    liveClass: ClassRecord,
    session: SessionRecord,
    participantCount: number,
  ): Promise<SessionRecord> {
    if (!session.egressId || session.recordingEndedAt) return session;
    const endedAt = this.clock();
    await this.writeMetadata(liveClass, session, {
      egressIds: [session.egressId],
      actualEndAt: endedAt,
      participantCount,
    });
    await this.livekit.stopRecording(session.egressId);
    const next = await this.repo.updateSession(session.id, { recordingEndedAt: endedAt });
    const actor = await this.hub.find(session.id);
    if (actor && !actor.state.ended) {
      actor.submit({ kind: 'recording', recording: { active: false, startedAt: null } });
    }
    return next;
  }

  /** LiveKit reported the egress failed: make a lost recording visible rather than silent. */
  async failed(session: SessionRecord, error: string): Promise<void> {
    await this.repo.updateSession(session.id, {
      recordingError: error,
      recordingEndedAt: this.clock(),
    });
    await this.repo.appendAudit({
      id: newId('liveAudit'),
      sessionId: session.id,
      actorId: null,
      targetId: null,
      kind: 'recording.failed',
      detail: { error },
      createdAt: this.clock(),
    });
    const actor = await this.hub.find(session.id);
    if (actor && !actor.state.ended) {
      actor.submit({ kind: 'recording', recording: { active: false, startedAt: null } });
    }
  }

  private async writeMetadata(
    liveClass: ClassRecord,
    session: SessionRecord,
    extra: { egressIds: string[]; actualEndAt: Date | null; participantCount: number | null },
  ): Promise<void> {
    const metadata: RecordingMetadata = recordingMetadataSchema.parse({
      classId: liveClass.id,
      sessionId: session.id,
      courseId: liveClass.courseId,
      sectionId: liveClass.sectionId,
      title: liveClass.title,
      teacherId: liveClass.teacherId,
      scheduledStartAt: liveClass.scheduledStartAt?.toISOString() ?? null,
      actualStartAt: session.startedAt.toISOString(),
      actualEndAt: extra.actualEndAt?.toISOString() ?? null,
      participantCount: extra.participantCount,
      livekitRoom: session.id,
      egressIds: extra.egressIds,
    });
    await this.objects.putJson(
      `${RecordingService.prefix(liveClass.id, session.id)}/metadata.json`,
      metadata,
    );
  }
}
