import type { AddressInfo } from 'node:net';
import type { INestApplication } from '@nestjs/common';
import {
  DEFAULT_ROOM_POLICY,
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
    // Their name over their whole number: no short id, no clock.
    expect(aliJoin.watermark.text).toBe('علی کریمی\n09121234503');
    expect(aliJoin.watermark.movement).toBe('corners-and-center');
    expect(aliJoin.capturePolicy).toMatchObject({
      block: true,
      windowsAffinity: 'monitor',
      censorAudio: true,
    });
    expect(livekit.tokens.find((t) => t.identity === users.ali)).toMatchObject({ sources: [] });
    // The phone number never goes into LiveKit, where every participant could read it.
    expect(JSON.stringify(livekit.tokens)).not.toContain('1234503');

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
    // A whole number reaches its owner only: Ali's is in neither Sara's join nor her gateway
    // view of the class, nor in anyone's ticket.
    expect(saraJoin.watermark.text).toBe('سارا محمدی\n09121234504');
    expect(JSON.stringify(saraJoin)).not.toContain('1234503');
    expect(JSON.stringify(sara.messages)).not.toContain('1234503');
    expect(JSON.stringify(host.messages)).not.toContain('1234503');
    for (const ticket of [aliJoin, hostJoin, saraJoin].map((j) => j.gateway.ticket)) {
      const claims = Buffer.from(ticket.split('.')[1] ?? '', 'base64url').toString();
      expect(claims).toContain('"sid"');
      expect(claims).not.toContain('1234503');
    }
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

describe('private chat in a live class', () => {
  let liveClass: LiveClass;
  let session: LiveSession;
  let host: TestClient;
  let ali: TestClient;
  let sara: TestClient;
  /** Sara's position before Ali's private message: what she reconnects from. */
  let saraSeqBefore = 0;
  let aliPrivateId = '';
  let saraPrivateId = '';

  const join = async (who: 'teacher' | 'ali' | 'sara', lastSeq: number | null = null) => {
    const res = joinResponseSchema.parse(
      (await call('POST', `/sessions/${session.id}/join`, who)).body,
    );
    return TestClient.connect(wsUrl, res.gateway.ticket, lastSeq);
  };
  const chatTexts = (c: TestClient) =>
    c.events().flatMap((e) => (e.type === 'chat.message' ? [e.message.text] : []));
  const said = (c: TestClient, text: string) =>
    c.waitFor((m) => m.t === 'evt' && m.evt.type === 'chat.message' && m.evt.message.text === text);
  const policySeen = (c: TestClient, on: boolean) =>
    c.waitFor(
      (m) => m.t === 'evt' && m.evt.type === 'policy.updated' && m.evt.policy.privateChat === on,
    );

  it('starts a class with private chat off, and everyone sees the setting', async () => {
    liveClass = liveClassSchema.parse(
      (
        await call('POST', '/classes', 'teacher', {
          courseId: COURSE,
          title: 'ریاضی ۱ — گفتگوی خصوصی',
          settings: { autoRecord: false },
        })
      ).body,
    );
    expect(liveClass.settings.policy.privateChat).toBe(false);
    session = liveSessionSchema.parse(
      (await call('POST', `/classes/${liveClass.id}/sessions`, 'teacher')).body,
    );
    host = await join('teacher');
    ali = await join('ali');
    sara = await join('sara');
    expect(sara.welcome.snapshot?.policy.privateChat).toBe(false);
  });

  it('refuses a student who tries to switch it, over the gateway and over REST', async () => {
    expect(
      await ali.command({ type: 'policy.update', patch: { privateChat: true } }),
    ).toMatchObject({ t: 'nack', error: { code: 'CAPABILITY_MISSING' } });
    const patch = await call('PATCH', `/classes/${liveClass.id}`, 'ali', {
      settings: { policy: { ...DEFAULT_ROOM_POLICY, privateChat: true } },
    });
    expect(patch.status).toBe(403);
    expect(
      (await call<LiveClass>('GET', `/classes/${liveClass.id}`, 'ali')).body.settings.policy,
    ).toMatchObject({ privateChat: false });
    expect(host.events().some((e) => e.type === 'policy.updated')).toBe(false);
  });

  it('lets the teacher turn it on mid-class, and tells every client at once', async () => {
    expect(
      await host.command({ type: 'policy.update', patch: { privateChat: true } }),
    ).toMatchObject({ t: 'ack' });
    await Promise.all([policySeen(host, true), policySeen(ali, true), policySeen(sara, true)]);
  });

  it('shows a student their own message, and the teacher — never another student', async () => {
    saraSeqBefore = sara.lastSeq;
    expect(await ali.command({ type: 'chat.send', text: 'سوال علی' })).toMatchObject({ t: 'ack' });
    const own = await said(ali, 'سوال علی');
    const atHost = await said(host, 'سوال علی');
    expect(own).toMatchObject({ evt: { message: { private: true, userId: users.ali } } });
    expect(atHost).toMatchObject({ evt: { message: { private: true } } });
    if (atHost.t === 'evt' && atHost.evt.type === 'chat.message')
      aliPrivateId = atHost.evt.message.id;

    // The teacher's reply is public: when Sara has it, Ali's question would have come first.
    await host.command({ type: 'chat.send', text: 'پاسخ استاد' });
    expect(await said(sara, 'پاسخ استاد')).toMatchObject({ evt: { message: { private: false } } });
    expect(chatTexts(sara)).not.toContain('سوال علی');
  });

  it('lets the second student write too, unseen by the first', async () => {
    await sara.command({ type: 'chat.send', text: 'سوال سارا' });
    await said(sara, 'سوال سارا');
    const atHost = await said(host, 'سوال سارا');
    if (atHost.t === 'evt' && atHost.evt.type === 'chat.message')
      saraPrivateId = atHost.evt.message.id;
    await host.command({ type: 'chat.send', text: 'مرز' });
    await said(ali, 'مرز');
    expect(chatTexts(ali)).not.toContain('سوال سارا');
    expect(chatTexts(sara)).not.toContain('سوال علی');
  });

  it('does not let a student probe or delete another student’s message by id', async () => {
    expect(await ali.command({ type: 'chat.delete', messageId: saraPrivateId })).toMatchObject({
      t: 'nack',
      error: { code: 'NOT_FOUND' },
    });
  });

  it('keeps the rule across a refresh (snapshot) and a reconnect (replay)', async () => {
    sara.close();
    sara = await join('sara');
    const history = sara.welcome.snapshot!.chat.map((m) => m.text);
    expect(history).toEqual(expect.arrayContaining(['پاسخ استاد', 'سوال سارا', 'مرز']));
    expect(history).not.toContain('سوال علی');
    expect(sara.welcome.snapshot!.policy.privateChat).toBe(true);

    const lastSeq = sara.lastSeq;
    sara.close();
    await host.waitFor(
      (m) =>
        m.t === 'evt' &&
        m.evt.type === 'participant.updated' &&
        m.evt.participant.userId === users.sara &&
        !m.evt.participant.online &&
        m.seq > lastSeq,
    );
    sara = await join('sara', saraSeqBefore);
    expect(sara.welcome.snapshot).toBeNull();
    const replayed = sara.welcome.replay!.flatMap((e) =>
      e.evt.type === 'chat.message' ? [e.evt.message.text] : [],
    );
    expect(replayed).toEqual(['پاسخ استاد', 'سوال سارا', 'مرز']);

    // The teacher's own refresh still has every message.
    host.close();
    host = await join('teacher');
    expect(host.welcome.snapshot!.chat.map((m) => m.text)).toEqual(
      expect.arrayContaining(['سوال علی', 'سوال سارا']),
    );
  });

  it('keeps the rest of the class working while it is on', async () => {
    // Another toggle changing leaves private chat as it was.
    await host.command({ type: 'policy.update', patch: { participantsCanDraw: true } });
    expect(
      await sara.waitFor(
        (m) => m.t === 'evt' && m.evt.type === 'policy.updated' && m.evt.policy.participantsCanDraw,
      ),
    ).toMatchObject({ evt: { policy: { privateChat: true } } });

    expect(await sara.command({ type: 'hand.raise' })).toMatchObject({ t: 'ack' });
    await ali.waitFor(
      (m) =>
        m.t === 'evt' &&
        m.evt.type === 'participant.updated' &&
        m.evt.participant.userId === users.sara &&
        m.evt.participant.hand !== null,
    );
    expect(await host.command({ type: 'chat.delete', messageId: aliPrivateId })).toMatchObject({
      t: 'ack',
    });
    await ali.waitFor((m) => m.t === 'evt' && m.evt.type === 'chat.deleted');
  });

  it('returns to public chat when the teacher turns it off, without publishing what was private', async () => {
    await host.command({ type: 'policy.update', patch: { privateChat: false } });
    await Promise.all([policySeen(ali, false), policySeen(sara, false)]);
    await ali.command({ type: 'chat.send', text: 'حالا همه می‌بینند' });
    expect(await said(sara, 'حالا همه می‌بینند')).toMatchObject({
      evt: { message: { private: false } },
    });

    sara.close();
    sara = await join('sara');
    const history = sara.welcome.snapshot!.chat.map((m) => m.text);
    expect(history).toContain('حالا همه می‌بینند');
    expect(history).toContain('سوال سارا');
    ali.close();
    ali = await join('ali');
    expect(ali.welcome.snapshot!.chat.map((m) => m.text)).not.toContain('سوال سارا');
  });

  it('can be switched on and off again in the same class', async () => {
    await host.command({ type: 'policy.update', patch: { privateChat: true } });
    await policySeen(sara, true);
    await sara.command({ type: 'chat.send', text: 'دوباره خصوصی' });
    await said(host, 'دوباره خصوصی');
    await host.command({ type: 'policy.update', patch: { privateChat: false } });
    await policySeen(ali, false);
    expect(chatTexts(ali)).not.toContain('دوباره خصوصی');
  });

  it('lets the teacher make it the default for the class’s next sessions', async () => {
    const patched = await call<LiveClass>('PATCH', `/classes/${liveClass.id}`, 'teacher', {
      settings: { policy: { ...DEFAULT_ROOM_POLICY, privateChat: true } },
    });
    expect(patched.status).toBe(200);
    expect(liveClassSchema.parse(patched.body).settings.policy.privateChat).toBe(true);

    await call('POST', `/sessions/${session.id}/end`, 'teacher');
    session = liveSessionSchema.parse(
      (await call('POST', `/classes/${liveClass.id}/sessions`, 'teacher')).body,
    );
    const next = await join('sara');
    expect(next.welcome.snapshot!.policy.privateChat).toBe(true);
    expect(next.welcome.snapshot!.chat).toEqual([]);
    await call('POST', `/sessions/${session.id}/end`, 'teacher');
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
