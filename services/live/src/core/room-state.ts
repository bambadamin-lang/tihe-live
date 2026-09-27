import {
  DEFAULT_PAGE_BACKGROUND,
  SNAPSHOT_CHAT_LIMIT,
  type BoardItem,
  type BoardPage,
  type ChatMessage,
  type ClassroomEvent,
  type ClassroomSnapshot,
  type Layout,
  type ParticipantState,
  type RecordingState,
  type RoomPolicy,
  type SequencedEvent,
} from '@tihe/contracts';

/**
 * The server's copy of one classroom. It changes **only** by applying events (`applyEvent`),
 * the same events every client applies — so the server and every stage cannot disagree.
 */
export interface RoomState {
  sessionId: string;
  classId: string;
  title: string;
  startedAt: string;
  policy: RoomPolicy;
  layout: Layout;
  /** Insertion order is join order, which is what the participant list shows. */
  participants: Map<string, ParticipantState>;
  chat: ChatMessage[];
  board: {
    pages: BoardPage[];
    activePageId: string;
    /** Insertion order is sequence order, which is paint order. */
    items: Map<string, BoardItem>;
  };
  /**
   * Recently removed board items, kept so an undo can restore them *and* so the server knows
   * whose they were — a student may restore their own erased stroke, not someone else's.
   */
  tombstones: Map<string, BoardItem>;
  recording: RecordingState;
  /** Removed participants cannot come back to this session. */
  removed: Set<string>;
  ended: boolean;
  seq: number;
}

export const TOMBSTONE_LIMIT = 5000;

export interface NewRoom {
  sessionId: string;
  classId: string;
  title: string;
  startedAt: string;
  policy: RoomPolicy;
  layout: Layout;
  firstPageId: string;
}

export function createRoomState(room: NewRoom): RoomState {
  return {
    sessionId: room.sessionId,
    classId: room.classId,
    title: room.title,
    startedAt: room.startedAt,
    policy: { ...room.policy },
    layout: room.layout,
    participants: new Map(),
    chat: [],
    board: {
      pages: [{ id: room.firstPageId, background: DEFAULT_PAGE_BACKGROUND }],
      activePageId: room.firstPageId,
      items: new Map(),
    },
    tombstones: new Map(),
    recording: { active: false, startedAt: null },
    removed: new Set(),
    ended: false,
    seq: 0,
  };
}

/**
 * A room rebuilt from what a client receives in its welcome. Used by the Egress template, which
 * applies events with the very same `applyEvent` the server uses, so the recording cannot
 * drift from the live stage.
 */
export function roomStateFromSnapshot(snapshot: ClassroomSnapshot, seq: number): RoomState {
  return {
    sessionId: snapshot.sessionId,
    classId: snapshot.classId,
    title: snapshot.title,
    startedAt: snapshot.startedAt,
    policy: snapshot.policy,
    layout: snapshot.layout,
    participants: new Map(snapshot.participants.map((p) => [p.userId, p])),
    chat: [...snapshot.chat],
    board: {
      pages: [...snapshot.board.pages],
      activePageId: snapshot.board.activePageId,
      items: new Map(snapshot.board.items.map((i) => [i.id, i])),
    },
    tombstones: new Map(),
    recording: snapshot.recording,
    removed: new Set(),
    ended: false,
    seq,
  };
}

function bury(state: RoomState, item: BoardItem): void {
  state.board.items.delete(item.id);
  state.tombstones.set(item.id, item);
  if (state.tombstones.size > TOMBSTONE_LIMIT) {
    const oldest = state.tombstones.keys().next().value;
    if (oldest !== undefined) state.tombstones.delete(oldest);
  }
}

/** Apply one sequenced event. The Dart client's reducer mirrors this function. */
export function applyEvent(state: RoomState, sequenced: SequencedEvent): void {
  state.seq = sequenced.seq;
  const evt: ClassroomEvent = sequenced.evt;
  switch (evt.type) {
    case 'participant.joined':
    case 'participant.updated':
      state.participants.set(evt.participant.userId, evt.participant);
      return;
    case 'participant.removed':
      state.participants.delete(evt.userId);
      state.removed.add(evt.userId);
      return;
    case 'policy.updated':
      state.policy = evt.policy;
      return;
    case 'layout.applied':
      state.layout = evt.layout;
      return;
    case 'chat.message':
      state.chat.push(evt.message);
      if (state.chat.length > SNAPSHOT_CHAT_LIMIT)
        state.chat.splice(0, state.chat.length - SNAPSHOT_CHAT_LIMIT);
      return;
    case 'chat.deleted':
      state.chat = state.chat.filter((m) => m.id !== evt.messageId);
      return;
    case 'wb.added':
      for (const item of evt.items) {
        state.tombstones.delete(item.id);
        state.board.items.set(item.id, item);
      }
      return;
    case 'wb.removed':
      for (const id of evt.itemIds) {
        const item = state.board.items.get(id);
        if (item) bury(state, item);
      }
      return;
    case 'wb.cleared':
      for (const item of [...state.board.items.values()]) {
        if (item.pageId === evt.pageId) bury(state, item);
      }
      return;
    case 'wb.page.added':
      state.board.pages.push(evt.page);
      return;
    case 'wb.page.selected':
      state.board.activePageId = evt.pageId;
      return;
    case 'wb.page.removed':
      state.board.pages = state.board.pages.filter((p) => p.id !== evt.pageId);
      for (const item of [...state.board.items.values()]) {
        if (item.pageId === evt.pageId) state.board.items.delete(item.id);
      }
      return;
    case 'recording.changed':
      state.recording = evt.recording;
      return;
    case 'class.ended':
      state.ended = true;
      return;
    case 'capture.alert':
    case 'media.muted':
      // Notifications only; the participant's `capturing` flag travels in participant.updated.
      return;
  }
}

export function isManager(state: RoomState, userId: string): boolean {
  return state.participants.get(userId)?.caps.includes('participants.manage') ?? false;
}

/**
 * What one recipient may see of a participant. Capture status is for managers only: telling a
 * whole class that a named student was caught recording is the host's call, not the app's.
 */
export function redactParticipant(p: ParticipantState, viewerIsManager: boolean): ParticipantState {
  return viewerIsManager || !p.capturing ? p : { ...p, capturing: false };
}

export function redactEvent(evt: ClassroomEvent, viewerIsManager: boolean): ClassroomEvent {
  if (viewerIsManager) return evt;
  if (evt.type === 'participant.joined' || evt.type === 'participant.updated') {
    return { ...evt, participant: redactParticipant(evt.participant, false) };
  }
  return evt;
}

export function snapshotFor(state: RoomState, viewerId: string): ClassroomSnapshot {
  const manager = isManager(state, viewerId);
  return {
    sessionId: state.sessionId,
    classId: state.classId,
    title: state.title,
    startedAt: state.startedAt,
    policy: state.policy,
    layout: state.layout,
    participants: [...state.participants.values()].map((p) => redactParticipant(p, manager)),
    chat: [...state.chat],
    board: {
      pages: [...state.board.pages],
      activePageId: state.board.activePageId,
      items: [...state.board.items.values()],
    },
    recording: state.recording,
  };
}

/** Serializable form for Redis and for the final snapshot kept in Postgres. */
export interface PersistedRoom {
  state: Omit<RoomState, 'participants' | 'board' | 'tombstones' | 'removed'> & {
    participants: ParticipantState[];
    board: { pages: BoardPage[]; activePageId: string; items: BoardItem[] };
    tombstones: BoardItem[];
    removed: string[];
  };
}

export function persistRoom(state: RoomState): PersistedRoom {
  return {
    state: {
      ...state,
      participants: [...state.participants.values()],
      board: {
        pages: state.board.pages,
        activePageId: state.board.activePageId,
        items: [...state.board.items.values()],
      },
      tombstones: [...state.tombstones.values()],
      removed: [...state.removed],
    },
  };
}

export function restoreRoom(persisted: PersistedRoom): RoomState {
  const s = persisted.state;
  return {
    ...s,
    participants: new Map(s.participants.map((p) => [p.userId, p])),
    board: {
      pages: s.board.pages,
      activePageId: s.board.activePageId,
      items: new Map(s.board.items.map((i) => [i.id, i])),
    },
    tombstones: new Map(s.tombstones.map((i) => [i.id, i])),
    removed: new Set(s.removed),
  };
}
