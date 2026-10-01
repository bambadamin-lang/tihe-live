/**
 * How long the classroom gateway's room actor takes to fan events out to a full class, with
 * connections that serialise exactly as the gateway's WebSockets do. Run before and after a
 * change to the fan-out path:
 *
 *   pnpm --filter @tihe/live exec tsx scripts/fanout-bench.ts
 */
import { DEFAULT_ROOM_POLICY, LAYOUT_PRESETS, type ServerMessage } from '@tihe/contracts';
import { RoomActor, type Connection } from '../src/classroom/room-actor.js';
import { MemoryRoomStore } from '../src/classroom/room-store.js';
import { newId } from '../src/core/ids.js';
import { createRoomState } from '../src/core/room-state.js';

const STUDENTS = 100;
let bytes = 0;
// Simulated time, advanced per operation, so the actor's rate limits see a realistic pace.
let now = Date.now();

function connection(userId: string, role: Connection['role']): Connection {
  return {
    userId,
    role,
    // What the gateway does for each socket, minus the socket write itself.
    send: (msg: ServerMessage, frame?: string) => {
      bytes += (frame ?? JSON.stringify(msg)).length;
    },
    close: () => {},
    bufferedAmount: () => 0,
  };
}

const pageId = newId('boardPage');
const actor = new RoomActor(
  createRoomState({
    sessionId: newId('liveSession'),
    classId: newId('liveClass'),
    title: 'bench',
    startedAt: new Date().toISOString(),
    policy: DEFAULT_ROOM_POLICY,
    layout: LAYOUT_PRESETS.whiteboard,
    firstPageId: pageId,
  }),
  {
    clock: () => new Date(now),
    newId: (kind) => newId(kind),
    store: new MemoryRoomStore(),
    runEffect: async () => {},
    log: () => {},
  },
);

const host = connection(newId('user'), 'host');
actor.connect(host, 'teacher', null);
const students = Array.from({ length: STUDENTS }, () => connection(newId('user'), 'participant'));
for (const s of students) actor.connect(s, 'student', null);

function time(label: string, n: number, run: (i: number) => void): void {
  for (let i = 0; i < 200; i++) run(i); // warm up the JIT
  bytes = 0;
  const start = process.hrtime.bigint();
  for (let i = 0; i < n; i++) run(i);
  const ms = Number(process.hrtime.bigint() - start) / 1e6;
  console.log(
    `${label.padEnd(44)} ${(ms / n).toFixed(3).padStart(8)} ms each  ` +
      `${((bytes / n) * 1e-3).toFixed(1).padStart(7)} KB sent each`,
  );
}

const strokeId = newId('boardItem');
time(`board preview to ${STUDENTS} students`, 2000, (i) => {
  now += 40;
  actor.relay(host, {
    type: 'wb.progress',
    strokeId,
    pageId,
    tool: 'pen',
    color: '#1F4FD8',
    width: 30,
    points: Array.from({ length: 12 }, (_, k) => 1000 + i + k * 13),
    done: false,
  });
});

time(`chat message to ${STUDENTS + 1} people`, 1000, (i) => {
  now += 2000;
  actor.submit({
    kind: 'command',
    actorId: host.userId,
    cmd: { type: 'chat.send', text: `پیام ${i}` },
  });
});

time(`finished 600-point stroke to ${STUDENTS + 1} people`, 500, (i) => {
  now += 1000;
  actor.submit({
    kind: 'command',
    actorId: host.userId,
    cmd: {
      type: 'wb.add',
      item: {
        kind: 'stroke',
        id: newId('boardItem'),
        pageId,
        color: '#1F4FD8',
        tool: 'pen',
        width: 30,
        points: Array.from({ length: 600 }, (_, k) => (i * 7 + k * 11) % 9000),
      },
    },
  });
});
