import { Redis } from 'ioredis';
import type { AudiencedEvent } from '../core/room-reducer.js';
import type { PersistedRoom } from '../core/room-state.js';

/**
 * Hot storage for live rooms, so a restart of services/live resumes every class where it was:
 * a periodic snapshot plus the events since. Rooms are otherwise served from memory.
 */
export interface RoomStore {
  saveSnapshot(sessionId: string, room: PersistedRoom): Promise<void>;
  append(sessionId: string, events: AudiencedEvent[]): Promise<void>;
  load(sessionId: string): Promise<{ room: PersistedRoom; events: AudiencedEvent[] } | null>;
  remove(sessionId: string): Promise<void>;
}
export const ROOM_STORE = Symbol('ROOM_STORE');

/** A class that is abandoned without being ended does not linger in Redis forever. */
const TTL_SECONDS = 24 * 3600;

export class RedisRoomStore implements RoomStore {
  constructor(private readonly redis: Redis) {}

  private snapKey = (sid: string) => `live:room:${sid}:snapshot`;
  private eventsKey = (sid: string) => `live:room:${sid}:events`;

  async saveSnapshot(sessionId: string, room: PersistedRoom): Promise<void> {
    // The snapshot covers every event so far, so the event list restarts with it.
    await this.redis
      .multi()
      .set(this.snapKey(sessionId), JSON.stringify(room), 'EX', TTL_SECONDS)
      .del(this.eventsKey(sessionId))
      .exec();
  }

  async append(sessionId: string, events: AudiencedEvent[]): Promise<void> {
    if (events.length === 0) return;
    await this.redis
      .multi()
      .rpush(this.eventsKey(sessionId), ...events.map((e) => JSON.stringify(e)))
      .expire(this.eventsKey(sessionId), TTL_SECONDS)
      .exec();
  }

  async load(sessionId: string) {
    const [snap, events] = await Promise.all([
      this.redis.get(this.snapKey(sessionId)),
      this.redis.lrange(this.eventsKey(sessionId), 0, -1),
    ]);
    if (!snap) return null;
    const room = JSON.parse(snap) as PersistedRoom;
    return {
      room,
      events: events
        .map((e) => JSON.parse(e) as AudiencedEvent)
        .filter((e) => e.seq > room.state.seq),
    };
  }

  async remove(sessionId: string): Promise<void> {
    await this.redis.del(this.snapKey(sessionId), this.eventsKey(sessionId));
  }
}

export class MemoryRoomStore implements RoomStore {
  private readonly snapshots = new Map<string, string>();
  private readonly events = new Map<string, string[]>();

  async saveSnapshot(sessionId: string, room: PersistedRoom) {
    this.snapshots.set(sessionId, JSON.stringify(room));
    this.events.set(sessionId, []);
  }
  async append(sessionId: string, events: AudiencedEvent[]) {
    const list = this.events.get(sessionId) ?? [];
    list.push(...events.map((e) => JSON.stringify(e)));
    this.events.set(sessionId, list);
  }
  async load(sessionId: string) {
    const snap = this.snapshots.get(sessionId);
    if (!snap) return null;
    const room = JSON.parse(snap) as PersistedRoom;
    const events = (this.events.get(sessionId) ?? [])
      .map((e) => JSON.parse(e) as AudiencedEvent)
      .filter((e) => e.seq > room.state.seq);
    return { room, events };
  }
  async remove(sessionId: string) {
    this.snapshots.delete(sessionId);
    this.events.delete(sessionId);
  }
}
