import { DEFAULT_ROOM_POLICY, LAYOUT_PRESETS, type ServerMessage } from '@tihe/contracts';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { createRoomState } from '../core/room-state.js';
import { RoomActor, type Connection } from './room-actor.js';
import { MemoryRoomStore } from './room-store.js';

const PAGE = 'wbp_01J8ZD00000000000000000001';
const HOST = 'usr_01J8ZB00000000000000000001';
const STUDENTS = Array.from(
  { length: 20 },
  (_, i) => `usr_01J8ZB${String(100 + i).padStart(20, '0')}`,
);

/** A connection that keeps what it was sent, and the frame it would have written. */
function connection(userId: string, role: Connection['role']) {
  const sent: { msg: ServerMessage; frame: string | undefined }[] = [];
  const conn: Connection = {
    userId,
    role,
    send: (msg, frame) => sent.push({ msg, frame }),
    close: () => {},
    bufferedAmount: () => 0,
  };
  return { conn, sent };
}

function classroom() {
  let counter = 0;
  let now = Date.UTC(2026, 9, 1, 10);
  const actor = new RoomActor(
    createRoomState({
      sessionId: 'ses_01J8ZC00000000000000000001',
      classId: 'cls_01J8ZA00000000000000000001',
      title: 'ریاضی',
      startedAt: new Date(now).toISOString(),
      policy: DEFAULT_ROOM_POLICY,
      layout: LAYOUT_PRESETS.whiteboard,
      firstPageId: PAGE,
    }),
    {
      clock: () => new Date((now += 1000)),
      newId: (kind) =>
        `${kind === 'chatMessage' ? 'chm' : 'x'}_01J8ZF${String(++counter).padStart(20, '0')}`,
      store: new MemoryRoomStore(),
      runEffect: async () => {},
      log: () => {},
    },
  );
  const host = connection(HOST, 'host');
  actor.connect(host.conn, 'teacher', null);
  const students = STUDENTS.map((id) => connection(id, 'participant'));
  for (const s of students) actor.connect(s.conn, `student ${s.conn.userId.slice(-2)}`, null);
  for (const c of [host, ...students]) c.sent.length = 0;
  return { actor, host, students };
}

describe('fan-out serialises a message once, not once per connection', () => {
  afterEach(() => vi.restoreAllMocks());

  it('a board preview is stringified once for the whole class', () => {
    const { actor, host, students } = classroom();
    const stringify = vi.spyOn(JSON, 'stringify');
    actor.relay(host.conn, {
      type: 'wb.progress',
      strokeId: 'wbi_01J8ZE00000000000000000001',
      pageId: PAGE,
      tool: 'pen',
      color: '#1F4FD8',
      width: 30,
      points: [10, 20, 30, 40],
      done: false,
    });
    expect(stringify).toHaveBeenCalledTimes(1);
    const frames = new Set(students.map((s) => s.sent[0]?.frame));
    expect(frames.size).toBe(1);
    expect(JSON.parse([...frames][0]!)).toEqual(students[0]!.sent[0]!.msg);
  });

  it('an event goes out as one frame per kind of viewer, still redacted for non-managers', () => {
    const { actor, host, students } = classroom();
    const ali = students[0]!;
    actor.submit({
      kind: 'command',
      actorId: ali.conn.userId,
      cmd: {
        type: 'capture.report',
        capturing: true,
        signals: ['recorder_process'],
        detail: 'obs64.exe',
      },
    });

    const updated = (sent: typeof ali.sent) =>
      sent.find((s) => s.msg.t === 'evt' && s.msg.evt.type === 'participant.updated');
    const forHost = updated(host.sent)!;
    const forStudents = students.slice(1).map((s) => updated(s.sent)!);

    // The host manages the class and sees who is capturing; classmates do not.
    expect(JSON.parse(forHost.frame!).evt.participant.capturing).toBe(true);
    expect(new Set(forStudents.map((s) => s.frame)).size).toBe(1);
    expect(JSON.parse(forStudents[0]!.frame!).evt.participant.capturing).toBe(false);
    // Every frame says exactly what its message says.
    for (const s of [forHost, ...forStudents]) expect(JSON.parse(s.frame!)).toEqual(s.msg);
  });
});
