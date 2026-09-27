import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { DEFAULT_ROOM_POLICY, LAYOUT_PRESETS } from '@tihe/contracts';
import { Redis } from 'ioredis';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ClassroomHub } from '../src/classroom/classroom-hub.js';
import { RedisRoomStore } from '../src/classroom/room-store.js';
import { MemoryLiveRepository } from '../src/persistence/memory-repository.js';
import { PrismaLiveRepository } from '../src/persistence/prisma-repository.js';
import { FakeLiveKit } from './fakes.js';

/**
 * Against real Postgres and Redis. Skipped unless LIVE_TEST_DATABASE_URL / LIVE_TEST_REDIS_URL
 * are set — CI sets both; locally:
 *
 *   LIVE_TEST_DATABASE_URL=postgresql://tihe:tihe_dev_password@localhost:5432/tihe_live \
 *   LIVE_TEST_REDIS_URL=redis://localhost:6379 pnpm --filter @tihe/live test
 */
const DB = process.env.LIVE_TEST_DATABASE_URL;
const REDIS = process.env.LIVE_TEST_REDIS_URL;

const CLASS = 'cls_01J8ZA000000000000000000T1';
const SESSION = 'ses_01J8ZC000000000000000000T1';
const USER = 'usr_01J8ZB00000000000000000003';

describe.skipIf(!DB)('PrismaLiveRepository (Postgres tihe_live)', () => {
  let repo: PrismaLiveRepository;

  beforeAll(async () => {
    execFileSync('npx', ['prisma', 'migrate', 'deploy'], {
      cwd: fileURLToPath(new URL('..', import.meta.url)),
      env: { ...process.env, LIVE_DATABASE_URL: DB },
      stdio: 'ignore',
    });
    repo = new PrismaLiveRepository(DB!);
    await repo.prisma.$executeRawUnsafe(
      'TRUNCATE live_audit_events, live_attendance, live_sessions, live_classes, saved_layouts',
    );
  });
  afterAll(async () => repo?.prisma.$disconnect());

  it('stores classes with validated settings and finds the live session', async () => {
    await repo.createClass({
      id: CLASS,
      courseId: 'crs_01J8ZA00000000000000000001',
      sectionId: null,
      title: 'ریاضی ۱',
      description: null,
      teacherId: 'usr_01J8ZB00000000000000000001',
      scheduledStartAt: new Date('2026-09-27T08:00:00Z'),
      durationMinutes: 90,
      settings: {
        autoRecord: true,
        defaultLayout: 'lecture',
        policy: DEFAULT_ROOM_POLICY,
        maxParticipants: 100,
      },
      createdAt: new Date(),
    });
    expect((await repo.findClass(CLASS))?.settings.policy).toEqual(DEFAULT_ROOM_POLICY);
    expect(await repo.listClasses({ courseId: 'crs_01J8ZA00000000000000000001' })).toHaveLength(1);

    await repo.createSession({
      id: SESSION,
      classId: CLASS,
      status: 'live',
      startedAt: new Date(),
      endedAt: null,
      egressId: null,
      recordingStartedAt: null,
      recordingEndedAt: null,
      recordingError: null,
      peakParticipants: 0,
    });
    expect((await repo.findLiveSession(CLASS))?.id).toBe(SESSION);
    await repo.updateSession(SESSION, { status: 'ended', finalSnapshot: { board: [] } });
    expect(await repo.findLiveSession(CLASS)).toBeNull();
  });

  it('sums attendance across reconnects and counts capture attempts', async () => {
    const at = (s: number) => new Date(Date.UTC(2026, 8, 27, 8, 0, s));
    const who = { userId: USER, name: 'علی', role: 'participant' as const };
    await repo.recordAttendance(SESSION, { ...who, change: 'join', at: at(0) });
    await repo.recordAttendance(SESSION, { ...who, change: 'leave', at: at(30) });
    await repo.recordAttendance(SESSION, { ...who, change: 'join', at: at(40) });
    await repo.recordAttendance(SESSION, { ...who, change: 'capture', at: at(45) });
    await repo.recordAttendance(SESSION, { ...who, change: 'leave', at: at(50) });
    const [row] = await repo.listAttendance(SESSION);
    expect(row).toMatchObject({
      secondsPresent: 40,
      joinCount: 2,
      captureAttempts: 1,
      openSince: null,
    });
  });

  it('appends audit events and scopes saved layouts to their owner', async () => {
    await repo.appendAudit({
      id: 'lae_01J8ZF00000000000000000001',
      sessionId: SESSION,
      actorId: USER,
      targetId: USER,
      kind: 'capture.detected',
      detail: { signals: ['recorder_process'] },
      createdAt: new Date(),
    });
    expect((await repo.listAudit(SESSION))[0]?.detail).toEqual({ signals: ['recorder_process'] });

    await repo.saveLayout({
      id: 'lay_01J8ZF00000000000000000001',
      ownerId: USER,
      name: 'x',
      pods: LAYOUT_PRESETS.qa.pods,
      createdAt: new Date(),
    });
    expect(
      await repo.deleteLayout('lay_01J8ZF00000000000000000001', 'usr_01J8ZB00000000000000000001'),
    ).toBe(false);
    expect(await repo.listLayouts(USER)).toHaveLength(1);
    expect(await repo.deleteLayout('lay_01J8ZF00000000000000000001', USER)).toBe(true);
  });
});

describe.skipIf(!REDIS)('RedisRoomStore: a restart resumes the class', () => {
  let redis: Redis;
  beforeAll(() => {
    redis = new Redis(REDIS!);
  });
  afterAll(async () => {
    await redis.del(`live:room:${SESSION}:snapshot`, `live:room:${SESSION}:events`);
    redis.disconnect();
  });

  it('restores board, hands and chat in a fresh process, with everyone offline', async () => {
    const clock = () => new Date();
    const hubA = new ClassroomHub(
      new RedisRoomStore(redis),
      new FakeLiveKit([]),
      new MemoryLiveRepository(),
      clock,
    );
    const actor = await hubA.open({
      sessionId: SESSION,
      classId: CLASS,
      title: 'ریاضی ۱',
      startedAt: clock().toISOString(),
      policy: DEFAULT_ROOM_POLICY,
      layout: LAYOUT_PRESETS.lecture,
      firstPageId: 'wbp_01J8ZD00000000000000000001',
    });
    actor.submit({ kind: 'join', userId: USER, name: 'علی', role: 'participant' });
    actor.submit({ kind: 'command', actorId: USER, cmd: { type: 'hand.raise' } });
    actor.submit({ kind: 'command', actorId: USER, cmd: { type: 'chat.send', text: 'سلام' } });
    await actor.flush();

    const hubB = new ClassroomHub(
      new RedisRoomStore(redis),
      new FakeLiveKit([]),
      new MemoryLiveRepository(),
      clock,
    );
    const restored = await hubB.find(SESSION);
    expect(restored?.state.seq).toBe(actor.state.seq);
    expect(restored?.state.chat.map((m) => m.text)).toEqual(['سلام']);
    const ali = restored?.state.participants.get(USER);
    expect(ali?.hand).not.toBeNull();
    expect(ali?.online).toBe(false);
  });
});
