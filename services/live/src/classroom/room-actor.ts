import {
  GATEWAY_CLOSE_CODES,
  type BoardProgress,
  type ClassRole,
  type GatewayError,
  type SequencedEvent,
  type ServerMessage,
} from '@tihe/contracts';
import type { IdFactory } from '../core/ids.js';
import {
  execute,
  gatewayError,
  type AudiencedEvent,
  type Effect,
  type ExecuteResult,
  type RoomInput,
} from '../core/room-reducer.js';
import {
  isManager,
  persistRoom,
  redactEvent,
  snapshotFor,
  type RoomState,
} from '../core/room-state.js';
import type { RoomStore } from './room-store.js';

/** The wire form of an event for one recipient: no audience field, capture status redacted. */
function project(e: AudiencedEvent, viewerIsManager: boolean): SequencedEvent {
  return { t: 'evt', seq: e.seq, at: e.at, evt: redactEvent(e.evt, viewerIsManager) };
}

/** A message with its serialised frame, shared by every connection it goes to. */
interface Wire {
  msg: SequencedEvent;
  frame: string;
}

function wireOf(msg: SequencedEvent): Wire {
  return { msg, frame: JSON.stringify(msg) };
}

/** One WebSocket, as the actor sees it. Abstract so tests can use plain objects. */
export interface Connection {
  readonly userId: string;
  readonly role: ClassRole;
  /**
   * `frame` is `msg` already serialised, when the same message goes to many connections: a
   * class of a hundred would otherwise stringify every event and preview a hundred times.
   */
  send(msg: ServerMessage, frame?: string): void;
  close(code: number): void;
  /** Bytes queued but not yet sent: a slow client is skipped for ephemeral traffic. */
  bufferedAmount(): number;
}

export interface ActorDeps {
  clock: () => Date;
  newId: IdFactory;
  store: RoomStore;
  /** Side effects outside the room: LiveKit, audit log, attendance. Errors are logged, not thrown. */
  runEffect: (sessionId: string, effect: Effect) => Promise<void>;
  log: (message: string, err?: unknown) => void;
}

/** Events kept for replay to a reconnecting client. Older than this, it gets a snapshot. */
export const REPLAY_WINDOW = 1000;
/** Snapshot to the store every this many events, so a restart replays little. */
export const SNAPSHOT_EVERY = 100;
/** Whiteboard previews per second per person. A 40 ms batch cadence needs 25. */
export const EPHEMERAL_PER_SECOND = 60;
/** A client this far behind is not sent previews; the committed item still reaches it. */
export const SLOW_CLIENT_BYTES = 1_000_000;

/**
 * One live classroom: applies inputs strictly one at a time (JavaScript's single thread does the
 * serialising, because `execute` is synchronous), then fans events out to the right people,
 * persists them, and runs their side effects. See ADR-0010.
 */
export class RoomActor {
  readonly log: AudiencedEvent[] = [];
  private readonly members = new Map<string, { conn: Connection; ready: boolean }>();
  private readonly recorders = new Set<Connection>();
  private readonly ephemeral = new Map<string, { second: number; count: number }>();
  private writes: Promise<void> = Promise.resolve();
  private sinceSnapshot = 0;

  constructor(
    readonly state: RoomState,
    private readonly deps: ActorDeps,
  ) {}

  get sessionId(): string {
    return this.state.sessionId;
  }

  /** People currently connected to the gateway (not the recorder). */
  get onlineCount(): number {
    return this.members.size;
  }

  submit(input: RoomInput): ExecuteResult {
    const result = execute(this.state, input, { now: this.deps.clock(), newId: this.deps.newId });
    if (!result.ok) return result;

    this.log.push(...result.events);
    if (this.log.length > REPLAY_WINDOW) this.log.splice(0, this.log.length - REPLAY_WINDOW);
    this.fanout(result.events);
    this.persist(result.events);
    for (const effect of result.effects) this.effect(effect);
    return result;
  }

  /**
   * A client said hello with a valid ticket. It is registered before its join is applied — but
   * not sent anything until its welcome — so it never sees an event before the state it applies to.
   */
  connect(conn: Connection, name: string, lastSeq: number | null): ExecuteResult | null {
    if (conn.role === 'recorder') {
      this.recorders.add(conn);
      conn.send({
        t: 'welcome',
        you: { userId: conn.userId, role: 'recorder' },
        seq: this.state.seq,
        snapshot: snapshotFor(this.state, conn.userId),
        replay: null,
      });
      return null;
    }

    const previous = this.members.get(conn.userId);
    if (previous) {
      // One seat per account: the newest connection wins, the old one is told why.
      this.members.delete(conn.userId);
      this.bye(
        previous.conn,
        GATEWAY_CLOSE_CODES.joinedElsewhere,
        gatewayError('JOINED_ELSEWHERE', 'joined from another device'),
      );
    }

    this.members.set(conn.userId, { conn, ready: false });
    const result = this.submit({ kind: 'join', userId: conn.userId, name, role: conn.role });
    if (!result.ok) {
      this.members.delete(conn.userId);
      this.bye(conn, GATEWAY_CLOSE_CODES.removed, result.error);
      return result;
    }

    const first = this.log[0];
    const canReplay = lastSeq !== null && first !== undefined && first.seq <= lastSeq + 1;
    const manager = isManager(this.state, conn.userId);
    conn.send({
      t: 'welcome',
      you: {
        userId: conn.userId,
        role: this.state.participants.get(conn.userId)?.role ?? conn.role,
      },
      seq: this.state.seq,
      snapshot: canReplay ? null : snapshotFor(this.state, conn.userId),
      replay: canReplay
        ? this.log
            .filter((e) => e.seq > lastSeq && this.reaches(e, conn.userId, manager))
            .map((e) => project(e, manager))
        : null,
    });
    const member = this.members.get(conn.userId);
    if (member?.conn === conn) member.ready = true;
    return result;
  }

  /** The socket closed. Only the user's current connection counts as leaving. */
  disconnect(conn: Connection): void {
    if (this.recorders.delete(conn)) return;
    if (this.members.get(conn.userId)?.conn !== conn) return;
    this.members.delete(conn.userId);
    if (!this.state.ended) this.submit({ kind: 'leave', userId: conn.userId });
  }

  /**
   * A whiteboard preview or laser trail. Checked like a command, relayed to everyone else, never
   * stored, and dropped for anyone who is too far behind or sending too fast.
   */
  relay(from: Connection, eph: BoardProgress): GatewayError | null {
    const p = this.state.participants.get(from.userId);
    if (!p?.caps.includes('whiteboard.draw')) {
      return gatewayError('CAPABILITY_MISSING', 'missing capability whiteboard.draw');
    }
    if (!this.state.board.pages.some((page) => page.id === eph.pageId)) return null;

    const second = Math.floor(this.deps.clock().getTime() / 1000);
    const budget = this.ephemeral.get(from.userId);
    if (budget && budget.second === second) {
      if (++budget.count > EPHEMERAL_PER_SECOND) return null;
    } else {
      this.ephemeral.set(from.userId, { second, count: 1 });
    }

    const msg: ServerMessage = { t: 'eph', from: from.userId, eph };
    const frame = JSON.stringify(msg);
    for (const { conn, ready } of this.members.values()) {
      if (ready && conn !== from && conn.bufferedAmount() < SLOW_CLIENT_BYTES) {
        conn.send(msg, frame);
      }
    }
    for (const rec of this.recorders) rec.send(msg, frame);
    return null;
  }

  /** End of class: everyone is told, then disconnected. */
  closeAll(error: GatewayError, code: number): void {
    for (const { conn } of this.members.values()) this.bye(conn, code, error);
    for (const rec of this.recorders) rec.close(code);
    this.members.clear();
    this.recorders.clear();
  }

  /** Waits for pending writes — used before a final snapshot and in tests. */
  async flush(): Promise<void> {
    await this.writes;
  }

  private reaches(e: AudiencedEvent, userId: string, manager: boolean): boolean {
    if (e.audience === 'all') return true;
    if (e.audience === 'managers') return manager;
    return e.audience.userId === userId;
  }

  private fanout(events: AudiencedEvent[]): void {
    // Each event is projected and serialised once per kind of viewer — managers see capture
    // status, others do not — and that one frame goes to everyone of that kind.
    const wire = events.map((e) => {
      const made: { manager?: Wire; member?: Wire } = {};
      return (manager: boolean): Wire => {
        const key = manager ? 'manager' : 'member';
        return (made[key] ??= wireOf(project(e, manager)));
      };
    });
    for (const { conn, ready } of this.members.values()) {
      if (!ready) continue;
      const manager = isManager(this.state, conn.userId);
      events.forEach((e, i) => {
        if (!this.reaches(e, conn.userId, manager)) return;
        const { msg, frame } = wire[i]!(manager);
        conn.send(msg, frame);
      });
    }
    // The recording shows the stage, never manager-only or personal notices.
    for (const rec of this.recorders) {
      events.forEach((e, i) => {
        if (e.audience !== 'all') return;
        const { msg, frame } = wire[i]!(false);
        rec.send(msg, frame);
      });
    }
  }

  private persist(events: AudiencedEvent[]): void {
    const sessionId = this.sessionId;
    this.sinceSnapshot += events.length;
    const snapshot = this.sinceSnapshot >= SNAPSHOT_EVERY ? persistRoom(this.state) : null;
    if (snapshot) this.sinceSnapshot = 0;
    this.writes = this.writes
      .then(() =>
        snapshot
          ? this.deps.store.saveSnapshot(sessionId, snapshot)
          : this.deps.store.append(sessionId, events),
      )
      .catch((err) => this.deps.log(`room ${sessionId}: persisting events failed`, err));
  }

  private effect(effect: Effect): void {
    if (effect.kind === 'disconnect') {
      const member = this.members.get(effect.userId);
      if (member) {
        this.members.delete(effect.userId);
        this.bye(member.conn, effect.closeCode, effect.error);
      }
      return;
    }
    this.deps
      .runEffect(this.sessionId, effect)
      .catch((err) => this.deps.log(`room ${this.sessionId}: effect ${effect.kind} failed`, err));
  }

  private bye(conn: Connection, code: number, error: GatewayError): void {
    conn.send({ t: 'bye', error });
    conn.close(code);
  }
}
