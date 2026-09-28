import { Inject, Injectable, Logger } from '@nestjs/common';
import { GATEWAY_CLOSE_CODES } from '@tihe/contracts';
import { newId } from '../core/ids.js';
import { gatewayError, type Effect } from '../core/room-reducer.js';
import {
  createRoomState,
  persistRoom,
  restoreRoom,
  applyEvent,
  type NewRoom,
  type PersistedRoom,
} from '../core/room-state.js';
import { LIVEKIT_PORT, type LiveKitPort } from '../livekit/livekit.port.js';
import { LIVE_REPOSITORY, type LiveRepository } from '../persistence/live-repository.js';
import { RoomActor } from './room-actor.js';
import { ROOM_STORE, type RoomStore } from './room-store.js';

export const CLOCK = Symbol('CLOCK');
export type Clock = () => Date;

/** Every live classroom this process serves, and the side effects their events cause. */
@Injectable()
export class ClassroomHub {
  private readonly logger = new Logger('ClassroomHub');
  private readonly rooms = new Map<string, RoomActor>();
  private readonly peaks = new Map<string, number>();

  constructor(
    @Inject(ROOM_STORE) private readonly store: RoomStore,
    @Inject(LIVEKIT_PORT) private readonly livekit: LiveKitPort,
    @Inject(LIVE_REPOSITORY) private readonly repo: LiveRepository,
    @Inject(CLOCK) private readonly clock: Clock,
  ) {}

  async open(room: NewRoom): Promise<RoomActor> {
    const actor = this.actorFor(createRoomState(room));
    this.rooms.set(room.sessionId, actor);
    await this.store.saveSnapshot(room.sessionId, persistRoom(actor.state));
    return actor;
  }

  /** The room in memory, or restored from the store after a restart. */
  async find(sessionId: string): Promise<RoomActor | null> {
    const live = this.rooms.get(sessionId);
    if (live) return live;
    const saved = await this.store.load(sessionId);
    if (!saved) return null;
    const state = restoreRoom(saved.room);
    for (const e of saved.events) applyEvent(state, e);
    // Nobody is connected to a freshly restored room; they reconnect and rejoin.
    for (const p of state.participants.values())
      state.participants.set(p.userId, { ...p, online: false });
    const actor = this.actorFor(state);
    this.rooms.set(sessionId, actor);
    this.logger.log(`restored room ${sessionId} at seq ${state.seq}`);
    return actor;
  }

  /** Disconnect everyone and forget the room. Returns its final state for the archive. */
  async close(sessionId: string): Promise<PersistedRoom | null> {
    const actor = this.rooms.get(sessionId) ?? (await this.find(sessionId));
    if (!actor) return null;
    actor.closeAll(gatewayError('CLASS_ENDED', 'class ended'), GATEWAY_CLOSE_CODES.classEnded);
    await actor.flush();
    this.rooms.delete(sessionId);
    this.peaks.delete(sessionId);
    await this.store.remove(sessionId);
    return persistRoom(actor.state);
  }

  peak(sessionId: string): number {
    return this.peaks.get(sessionId) ?? 0;
  }

  private actorFor(state: ReturnType<typeof createRoomState>): RoomActor {
    return new RoomActor(state, {
      clock: this.clock,
      newId: (kind) => newId(kind, this.clock().getTime()),
      store: this.store,
      runEffect: (sessionId, effect) => this.runEffect(sessionId, effect),
      log: (message, err) => this.logger.error(message, err instanceof Error ? err.stack : err),
    });
  }

  private async runEffect(sessionId: string, effect: Effect): Promise<void> {
    switch (effect.kind) {
      case 'livekit.permissions':
        return this.livekit.setPublishSources(sessionId, effect.userId, effect.sources);
      case 'livekit.mute':
        return this.livekit.muteTracks(sessionId, effect.userId, effect.media);
      case 'livekit.remove':
        return this.livekit.removeParticipant(sessionId, effect.userId);
      case 'audit':
        return this.repo.appendAudit({
          id: newId('liveAudit'),
          sessionId,
          ...effect.audit,
          createdAt: this.clock(),
        });
      case 'attendance': {
        await this.repo.recordAttendance(sessionId, { ...effect, at: new Date(effect.at) });
        if (effect.change === 'join') {
          const online = this.rooms.get(sessionId)?.onlineCount ?? 0;
          if (online > this.peak(sessionId)) this.peaks.set(sessionId, online);
        }
        return;
      }
      case 'disconnect':
        return; // handled by the actor itself
    }
  }
}
