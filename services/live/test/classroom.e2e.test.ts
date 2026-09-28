import type { AddressInfo } from 'node:net';
import type { INestApplication } from '@nestjs/common';
import {
  GATEWAY_CLOSE_CODES,
  errorResponseSchema,
  joinResponseSchema,
  liveClassSchema,
  liveSessionSchema,
  recordingMetadataSchema,
  type JoinResponse,
  type LiveClass,
  type LiveSession,
} from '@tihe/contracts';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import {
  Hs256AccessTokenVerifier,
  mintDevAccessToken,
  type Caller,
} from '../src/auth/access-token.js';
import { TicketService } from '../src/auth/tickets.js';
import { createLiveApp } from '../src/bootstrap.js';
import { MemoryRoomStore } from '../src/classroom/room-store.js';
import { loadConfig } from '../src/config.js';
import { StubCourseDirectory } from '../src/directory/stub-directory.js';
import { MemoryLiveRepository } from '../src/persistence/memory-repository.js';
import { FakeLiveKit, TracingObjectStore } from './fakes.js';
import { TestClient } from './ws-client.js';

const JWT_SECRET = 'test-jwt-secret-000000000000000000000000';
const COURSE = 'crs_01J8ZA00000000000000000001';
const users = {
  teacher: 'usr_01J8ZB00000000000000000001',
  ali: 'usr_01J8ZB00000000000000000003',
  sara: 'usr_01J8ZB00000000000000000004',
  outsider: 'usr_01J8ZB00000000000000000009',
};

const config = loadConfig({
  NODE_ENV: 'test',
  JWT_SECRET,
  LIVE_TICKET_SECRET: 'test-ticket-secret-00000000000000000000000',
  LIVEKIT_URL: 'ws://livekit.test:7880',
  LIVEKIT_API_KEY: 'devkey',
  LIVEKIT_API_SECRET: 'devsecret_change_me_in_production_00000000',
});

const timeline: string[] = [];
const livekit = new FakeLiveKit(timeline);
const objects = new TracingObjectStore(timeline);
const repo = new MemoryLiveRepository();
let app: INestApplication;
let base: string;
let wsUrl: string;
const tokens: Record<keyof typeof users, string> = { teacher: '', ali: '', sara: '', outsider: '' };

async function call<T>(method: string, path: string, who: keyof typeof users, body?: unknown) {
  const res = await fetch(`${base}${path}`, {
    method,
    headers: { authorization: `Bearer ${tokens[who]}`, 'content-type': 'application/json' },
    ...(body !== undefined && { body: JSON.stringify(body) }),
  });
  const text = await res.text();
  return { status: res.status, body: (text ? JSON.parse(text) : null) as T };
}

beforeAll(async () => {
  app = await createLiveApp(
    {
      config,
      repo,
      store: new MemoryRoomStore(),
      livekit,
      directory: new StubCourseDirectory({
        users: [
          { id: users.teacher, displayName: 'دکتر رضایی', phone: '+989121234501', role: 'teacher' },
          { id: users.ali, displayName: 'علی کریمی', phone: '+989121234503', role: 'student' },
          { id: users.sara, displayName: 'سارا محمدی', phone: '+989121234504', role: 'student' },
          { id: users.outsider, displayName: 'غریبه', phone: '+989121234509', role: 'student' },
        ],
        courses: [
          {
            id: COURSE,
            title: 'ریاضی ۱',
            teacherId: users.teacher,
            allowCapture: false,
            enrolled: [users.ali, users.sara],
          },
        ],
      }),
      objects,
      verifier: new Hs256AccessTokenVerifier(JWT_SECRET),
      tickets: new TicketService(
        config.LIVE_TICKET_SECRET,
        config.LIVEKIT_API_KEY,
        config.LIVEKIT_API_SECRET,
      ),
      clock: () => new Date(),
    },
    { logger: false },
  );
  await app.listen(0);
  const { port } = app.getHttpServer().address() as AddressInfo;
  base = `http://127.0.0.1:${port}/v1/live`;
  wsUrl = `ws://127.0.0.1:${port}/v1/live/ws`;
  for (const [who, userId] of Object.entries(users) as [keyof typeof users, string][]) {
    const caller: Caller = {
      userId,
      accountRole: who === 'teacher' ? 'teacher' : 'student',
      deviceId: 'dev_01J8ZB00000000000000000001',
    };
    tokens[who] = await mintDevAccessToken(JWT_SECRET, caller);
  }
});

afterAll(async () => {
  await app?.close();
});

describe('a live class from start to end', () => {
  let liveClass: LiveClass;
  let session: LiveSession;
  let host: TestClient;
  let ali: TestClient;
  let sara: TestClient;
  let aliJoin: JoinResponse;

  it('refuses requests without a valid access token, in the shared envelope', async () => {
    const res = await fetch(`${base}/classes`);
    const body = errorResponseSchema.parse(await res.json());
    expect(res.status).toBe(401);
    expect(body.error.code).toBe('UNAUTHENTICATED');
    expect(body.error.messageFa).toBeTruthy();
  });

  it('lets the course teacher create a class, and nobody else', async () => {
    const denied = await call('POST', '/classes', 'ali', { courseId: COURSE, title: 'x' });
    expect(denied.status).toBe(403);

    const created = await call<LiveClass>('POST', '/classes', 'teacher', {
      courseId: COURSE,
      title: 'ریاضی ۱ — جلسه ۴',
      settings: { defaultLayout: 'whiteboard' },
    });
    expect(created.status).toBe(201);
    liveClass = liveClassSchema.parse(created.body);
    expect(liveClass.settings.autoRecord).toBe(true);
  });

  it('hides the class from people who are not enrolled', async () => {
    expect((await call('GET', `/classes/${liveClass.id}`, 'outsider')).status).toBe(404);
    expect((await call('GET', `/classes/${liveClass.id}`, 'ali')).status).toBe(200);
  });

  it('starts the session: room created, recording started, metadata.json written first', async () => {
    expect((await call('POST', `/classes/${liveClass.id}/sessions`, 'ali')).status).toBe(403);
    const started = await call<LiveSession>('POST', `/classes/${liveClass.id}/sessions`, 'teacher');
    expect(started.status).toBe(201);
    session = liveSessionSchema.parse(started.body);
    expect(session.recording.active).toBe(true);

    const prefix = `recordings/${liveClass.id}/${session.id}`;
    expect(livekit.rooms.has(session.id)).toBe(true);
    expect(livekit.recordings[0]).toMatchObject({
      room: session.id,
      filepath: `${prefix}/composite.mp4`,
    });
    expect(livekit.recordings[0]!.templateUrl).toContain(`session=${session.id}`);
    const metadata = recordingMetadataSchema.parse(objects.objects.get(`${prefix}/metadata.json`));
    expect(metadata).toMatchObject({
      courseId: COURSE,
      livekitRoom: session.id,
      egressIds: ['EG_fake0001'],
    });
    expect(timeline.indexOf(`s3.put ${prefix}/metadata.json initial`)).toBeLessThan(
      timeline.indexOf(`livekit.startRecording ${prefix}/composite.mp4`),
    );

    const again = await call<LiveSession>('POST', `/classes/${liveClass.id}/sessions`, 'teacher');
    expect(again.body.id).toBe(session.id);
  });

  it('joins with a watermark, capture policy and LiveKit rights that match the role', async () => {
    const res = await call<JoinResponse>('POST', `/sessions/${session.id}/join`, 'ali');
    expect(res.status).toBe(200);
    aliJoin = joinResponseSchema.parse(res.body);
    expect(aliJoin.you.role).toBe('participant');
    expect(aliJoin.watermark.text).toMatch(/^0912•••4503 · #\d{5}$/);
    expect(aliJoin.watermark.movement).toBe('corners');
    expect(aliJoin.capturePolicy).toMatchObject({
      block: true,
      windowsAffinity: 'monitor',
      censorAudio: true,
    });
    expect(livekit.tokens.find((t) => t.identity === users.ali)).toMatchObject({ sources: [] });
    // The phone number never goes into LiveKit, where every participant could read it.
    expect(JSON.stringify(livekit.tokens)).not.toContain('4503');

    const hostJoin = joinResponseSchema.parse(
      (await call('POST', `/sessions/${session.id}/join`, 'teacher')).body,
    );
    expect(hostJoin.you.role).toBe('host');
    expect(hostJoin.capturePolicy.windowsAffinity).toBe('exclude');
    expect(livekit.tokens.find((t) => t.identity === users.teacher)!.sources).toContain(
      'screen_share',
    );

    const outsider = await call('POST', `/sessions/${session.id}/join`, 'outsider');
    expect(outsider.status).toBe(404);

    host = await TestClient.connect(wsUrl, hostJoin.gateway.ticket);
    ali = await TestClient.connect(wsUrl, aliJoin.gateway.ticket);
    const saraJoin = joinResponseSchema.parse(
      (await call('POST', `/sessions/${session.id}/join`, 'sara')).body,
    );
    sara = await TestClient.connect(wsUrl, saraJoin.gateway.ticket);

    expect(host.welcome.snapshot?.layout.id).toBe('whiteboard');
    expect(sara.welcome.snapshot?.participants.map((p) => p.userId)).toEqual([
      users.teacher,
      users.ali,
      users.sara,
    ]);
    await host.waitFor(
      (m) =>
        m.t === 'evt' &&
        m.evt.type === 'participant.joined' &&
        m.evt.participant.userId === users.sara,
    );
  });

  it('refuses a forged ticket', async () => {
    const forged = await TestClient.connect(wsUrl, 'eyJhbGciOiJIUzI1NiJ9.forged.ticket-value');
    expect(forged.messages[0]).toMatchObject({ t: 'bye', error: { code: 'UNAUTHENTICATED' } });
    expect(await forged.waitForClose()).toBe(GATEWAY_CLOSE_CODES.unauthenticated);
  });

  it('raises a hand, gives the floor, and tells the SFU', async () => {
    expect(await ali.command({ type: 'hand.raise' })).toMatchObject({ t: 'ack' });
    await host.waitFor(
      (m) =>
        m.t === 'evt' && m.evt.type === 'participant.updated' && m.evt.participant.hand !== null,
    );

    expect(
      await sara.command({ type: 'floor.give', userId: users.ali, video: false }),
    ).toMatchObject({
      t: 'nack',
      error: { code: 'CAPABILITY_MISSING' },
    });
    expect(
      await host.command({ type: 'floor.give', userId: users.ali, video: false }),
    ).toMatchObject({ t: 'ack' });
    await ali.waitFor(
      (m) => m.t === 'evt' && m.evt.type === 'participant.updated' && m.evt.participant.floor,
    );
    await expect
      .poll(() => livekit.permissions)
      .toContainEqual({ identity: users.ali, sources: ['microphone'] });
  });

  it('alerts the host — and only the host — when a student records the screen', async () => {
    await ali.command({
      type: 'capture.report',
      capturing: true,
      signals: ['recorder_process'],
      detail: 'obs64.exe',
    });
    const alert = await host.waitFor((m) => m.t === 'evt' && m.evt.type === 'capture.alert');
    expect(alert).toMatchObject({
      evt: { userId: users.ali, capturing: true, detail: 'obs64.exe' },
    });

    await sara.waitFor(
      (m) =>
        m.t === 'evt' &&
        m.evt.type === 'participant.updated' &&
        m.evt.participant.userId === users.ali,
    );
    expect(sara.events().some((e) => e.type === 'capture.alert')).toBe(false);
    expect(
      sara.events().some((e) => e.type === 'participant.updated' && e.participant.capturing),
    ).toBe(false);

    await expect.poll(() => repo.audit.map((a) => a.kind)).toContain('capture.detected');
    await expect
      .poll(
        async () =>
          (await repo.listAttendance(session.id)).find((a) => a.userId === users.ali)
            ?.captureAttempts,
      )
      .toBe(1);
  });

  it('syncs the whiteboard: commits for everyone, previews relayed, drawing refused without rights', async () => {
    const pageId = host.welcome.snapshot!.board.activePageId;
    const item = {
      kind: 'stroke' as const,
      id: 'wbi_01J8ZE00000000000000000001',
      pageId,
      color: '#1F4FD8',
      tool: 'pen' as const,
      width: 30,
      points: [100, 100, 900, 700],
    };
    expect(
      await ali.command({
        type: 'wb.add',
        item: { ...item, id: 'wbi_01J8ZE00000000000000000002' },
      }),
    ).toMatchObject({
      t: 'nack',
      error: { code: 'CAPABILITY_MISSING' },
    });
    expect(await host.command({ type: 'wb.add', item })).toMatchObject({ t: 'ack' });
    await sara.waitFor((m) => m.t === 'evt' && m.evt.type === 'wb.added');

    host.sendRaw({
      t: 'eph',
      eph: {
        type: 'wb.progress',
        strokeId: 'wbi_01J8ZE00000000000000000003',
        pageId,
        tool: 'laser',
        color: '#D32F2F',
        width: 60,
        points: [10, 10],
        done: false,
      },
    });
    const eph = await sara.waitFor((m) => m.t === 'eph');
    expect(eph).toMatchObject({ from: users.teacher });
    expect(host.messages.some((m) => m.t === 'eph')).toBe(false);
  });

  it('answers malformed commands with a nack instead of dropping the socket', async () => {
    sara.sendRaw({ t: 'cmd', id: 'bad1', cmd: { type: 'chat.send', text: '' } });
    expect(await sara.waitFor((m) => m.t === 'nack' && m.id === 'bad1')).toMatchObject({
      error: { code: 'VALIDATION_FAILED' },
    });
  });

  it('replays missed events to a reconnecting client instead of resending everything', async () => {
    const lastSeq = sara.lastSeq;
    sara.close();
    await host.waitFor(
      (m) =>
        m.t === 'evt' &&
        m.evt.type === 'participant.updated' &&
        m.evt.participant.userId === users.sara &&
        !m.evt.participant.online,
    );
    await host.command({ type: 'chat.send', text: 'دوباره سلام' });

    const rejoin = joinResponseSchema.parse(
      (await call('POST', `/sessions/${session.id}/join`, 'sara')).body,
    );
    sara = await TestClient.connect(wsUrl, rejoin.gateway.ticket, lastSeq);
    expect(sara.welcome.snapshot).toBeNull();
    const replayed = sara.welcome.replay!.map((e) => e.evt.type);
    expect(replayed).toContain('chat.message');
    expect(replayed.at(-1)).toBe('participant.updated');
  });

  it('keeps one seat per account: a second device replaces the first', async () => {
    const again = joinResponseSchema.parse(
      (await call('POST', `/sessions/${session.id}/join`, 'ali')).body,
    );
    const second = await TestClient.connect(wsUrl, again.gateway.ticket);
    expect(await ali.waitForClose()).toBe(GATEWAY_CLOSE_CODES.joinedElsewhere);
    expect(ali.messages.at(-1)).toMatchObject({ t: 'bye', error: { code: 'JOINED_ELSEWHERE' } });
    ali = second;
    // The room did not see ali leave: the seat moved.
    expect(ali.welcome.snapshot?.participants.find((p) => p.userId === users.ali)?.online).toBe(
      true,
    );
  });

  it('removes a participant for the rest of the session', async () => {
    expect(await host.command({ type: 'participant.remove', userId: users.sara })).toMatchObject({
      t: 'ack',
    });
    expect(await sara.waitForClose()).toBe(GATEWAY_CLOSE_CODES.removed);
    expect(livekit.removed).toContain(users.sara);
    const rejoin = await call<{ error: { code: string } }>(
      'POST',
      `/sessions/${session.id}/join`,
      'sara',
    );
    expect(rejoin.status).toBe(403);
    expect(rejoin.body.error.code).toBe('REMOVED_FROM_CLASS');
  });

  it('ends the class: final metadata before stopping egress, everyone disconnected, attendance kept', async () => {
    expect((await call('POST', `/sessions/${session.id}/end`, 'ali')).status).toBe(403);
    const ended = await call<LiveSession>('POST', `/sessions/${session.id}/end`, 'teacher');
    expect(ended.status).toBe(200);
    expect(liveSessionSchema.parse(ended.body)).toMatchObject({ status: 'ended' });

    const prefix = `recordings/${liveClass.id}/${session.id}`;
    const finalWrite = timeline.indexOf(`s3.put ${prefix}/metadata.json final`);
    expect(finalWrite).toBeGreaterThan(-1);
    expect(finalWrite).toBeLessThan(timeline.indexOf('livekit.stopRecording EG_fake0001'));
    const metadata = recordingMetadataSchema.parse(objects.objects.get(`${prefix}/metadata.json`));
    expect(metadata.actualEndAt).toBeTruthy();
    expect(metadata.participantCount).toBe(2);

    await host.waitFor((m) => m.t === 'evt' && m.evt.type === 'class.ended');
    expect(await host.waitForClose()).toBe(GATEWAY_CLOSE_CODES.classEnded);
    expect(livekit.rooms.has(session.id)).toBe(false);

    const attendance = await call<{ userId: string; secondsPresent: number }[]>(
      'GET',
      `/sessions/${session.id}/attendance`,
      'teacher',
    );
    expect(attendance.body.map((a) => a.userId).sort()).toEqual(
      [users.teacher, users.ali, users.sara].sort(),
    );
    expect((await call('POST', `/sessions/${session.id}/join`, 'ali')).status).toBe(410);
  });

  it('ignores LiveKit webhooks with a bad signature, and always answers 200', async () => {
    const res = await fetch(`${base}/webhooks/livekit`, {
      method: 'POST',
      headers: { authorization: 'forged', 'content-type': 'application/webhook+json' },
      body: JSON.stringify({ event: 'room_finished', roomName: session.id, egress: null }),
    });
    expect(res.status).toBe(200);
  });
});

describe('saved layouts', () => {
  it('saves a valid custom layout and refuses an overlapping one', async () => {
    const good = await call('POST', '/layouts', 'teacher', {
      name: 'تخته و دوربین',
      pods: [
        { id: 'wb', kind: 'whiteboard', x: 0, y: 0, w: 10, h: 12 },
        { id: 'sp', kind: 'speaker', x: 10, y: 0, w: 2, h: 3 },
      ],
    });
    expect(good.status).toBe(201);
    const bad = await call<{ error: { code: string } }>('POST', '/layouts', 'teacher', {
      name: 'x',
      pods: [
        { id: 'a', kind: 'whiteboard', x: 0, y: 0, w: 10, h: 12 },
        { id: 'b', kind: 'speaker', x: 9, y: 0, w: 3, h: 3 },
      ],
    });
    expect(bad.status).toBe(400);
    expect(bad.body.error.code).toBe('VALIDATION_FAILED');
    expect((await call<unknown[]>('GET', '/layouts', 'teacher')).body).toHaveLength(1);
    expect((await call('POST', '/layouts', 'ali', { name: 'x', pods: [] })).status).toBe(403);
  });
});
