import {
  DEFAULT_ROOM_POLICY,
  GATEWAY_CLOSE_CODES,
  LAYOUT_PRESETS,
  type BoardItemInput,
  type ClassRole,
  type ClassroomCommand,
} from '@tihe/contracts';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  CHAT_RATE,
  execute,
  type Effect,
  type ExecuteResult,
  type RoomInput,
} from './room-reducer.js';
import { createRoomState, snapshotFor, type RoomState } from './room-state.js';

const HOST = 'usr_01J8ZB00000000000000000001';
const COHOST = 'usr_01J8ZB00000000000000000002';
const ALI = 'usr_01J8ZB00000000000000000003';
const SARA = 'usr_01J8ZB00000000000000000004';
const PAGE = 'wbp_01J8ZD00000000000000000001';

let clock: number;
let counter: number;
const ctx = () => ({
  now: new Date(clock),
  newId: (kind: string) =>
    `${kind === 'chatMessage' ? 'chm' : 'x'}_01J8ZF${String(++counter).padStart(20, '0')}`,
});

let room: RoomState;
const run = (input: RoomInput): ExecuteResult => execute(room, input, ctx());
const cmd = (actorId: string, c: ClassroomCommand) => run({ kind: 'command', actorId, cmd: c });
const join = (userId: string, role: ClassRole, name = userId.slice(-4)) =>
  run({ kind: 'join', userId, name, role });

const ok = (r: ExecuteResult) => {
  if (!r.ok) throw new Error(`expected ok, got ${r.error.code}: ${r.error.message}`);
  return r;
};
const refused = (r: ExecuteResult) => {
  if (r.ok) throw new Error('expected refusal');
  return r.error.code;
};
const p = (userId: string) => room.participants.get(userId)!;
const effectsOf = <K extends Effect['kind']>(r: ExecuteResult, kind: K) =>
  ok(r).effects.filter((e): e is Extract<Effect, { kind: K }> => e.kind === kind);

const stroke = (id: string, pageId = PAGE): BoardItemInput => ({
  kind: 'stroke',
  id,
  pageId,
  color: '#1B1B1F',
  tool: 'pen',
  width: 30,
  points: [0, 0, 100, 100],
});
const W1 = 'wbi_01J8ZE00000000000000000001';
const W2 = 'wbi_01J8ZE00000000000000000002';

beforeEach(() => {
  clock = Date.UTC(2026, 8, 27, 6, 30);
  counter = 0;
  room = createRoomState({
    sessionId: 'ses_01J8ZC00000000000000000001',
    classId: 'cls_01J8ZA00000000000000000001',
    title: 'ریاضی ۱',
    startedAt: new Date(clock).toISOString(),
    policy: DEFAULT_ROOM_POLICY,
    layout: LAYOUT_PRESETS.lecture,
    firstPageId: PAGE,
  });
  ok(join(HOST, 'host'));
  ok(join(COHOST, 'cohost'));
  ok(join(ALI, 'participant'));
  ok(join(SARA, 'participant'));
});

describe('joining and leaving', () => {
  it('gives a new participant the capabilities of their role and the policy', () => {
    expect(p(ALI).caps).toEqual(['chat.send', 'hand.raise']);
    expect(p(ALI).online).toBe(true);
  });

  it('keeps a promotion across a rejoin instead of the ticket role', () => {
    ok(cmd(HOST, { type: 'role.set', userId: ALI, role: 'presenter' }));
    ok(run({ kind: 'leave', userId: ALI }));
    ok(join(ALI, 'participant'));
    expect(p(ALI).role).toBe('presenter');
  });

  it('lowers the hand and ends the floor when someone leaves', () => {
    ok(cmd(ALI, { type: 'hand.raise' }));
    ok(cmd(HOST, { type: 'floor.give', userId: SARA, video: false }));
    ok(run({ kind: 'leave', userId: ALI }));
    const r = ok(run({ kind: 'leave', userId: SARA }));
    expect(p(ALI).hand).toBeNull();
    expect(p(SARA).floor).toBe(false);
    expect(p(SARA).caps).not.toContain('publish.audio');
    expect(effectsOf(r, 'attendance')[0]).toMatchObject({ change: 'leave', userId: SARA });
  });

  it('refuses commands from someone who has left', () => {
    ok(run({ kind: 'leave', userId: ALI }));
    expect(refused(cmd(ALI, { type: 'hand.raise' }))).toBe('FORBIDDEN');
  });

  it('assigns increasing sequence numbers', () => {
    const r = ok(cmd(ALI, { type: 'hand.raise' }));
    expect(r.events[0]!.seq).toBe(room.seq);
    expect(room.seq).toBe(5);
  });
});

describe('raised hands', () => {
  it('queues hands in server order, not client time', () => {
    ok(cmd(SARA, { type: 'hand.raise' }));
    ok(cmd(ALI, { type: 'hand.raise' }));
    expect(p(SARA).hand!.raisedSeq).toBeLessThan(p(ALI).hand!.raisedSeq);
  });

  it('ignores raising an already raised hand', () => {
    ok(cmd(ALI, { type: 'hand.raise' }));
    expect(ok(cmd(ALI, { type: 'hand.raise' })).events).toEqual([]);
  });

  it('refuses a raised hand when the host disabled them', () => {
    ok(cmd(HOST, { type: 'policy.update', patch: { handRaiseEnabled: false } }));
    expect(refused(cmd(ALI, { type: 'hand.raise' }))).toBe('CAPABILITY_MISSING');
  });

  it('drops raised hands when the host disables them', () => {
    ok(cmd(ALI, { type: 'hand.raise' }));
    ok(cmd(HOST, { type: 'policy.update', patch: { handRaiseEnabled: false } }));
    expect(p(ALI).hand).toBeNull();
  });

  it('lets a student lower only their own hand', () => {
    ok(cmd(SARA, { type: 'hand.raise' }));
    expect(refused(cmd(ALI, { type: 'hand.lower', userId: SARA }))).toBe('CAPABILITY_MISSING');
    ok(cmd(SARA, { type: 'hand.lower' }));
    expect(p(SARA).hand).toBeNull();
  });

  it('lets a manager lower all hands at once', () => {
    ok(cmd(ALI, { type: 'hand.raise' }));
    ok(cmd(SARA, { type: 'hand.raise' }));
    const r = ok(cmd(COHOST, { type: 'hand.lowerAll' }));
    expect(r.events).toHaveLength(2);
    expect(p(ALI).hand).toBeNull();
  });
});

describe('the floor', () => {
  it('accepting a hand grants the microphone, lowers the hand and tells the SFU', () => {
    ok(cmd(ALI, { type: 'hand.raise' }));
    const r = ok(cmd(HOST, { type: 'floor.give', userId: ALI, video: false }));
    expect(p(ALI)).toMatchObject({ floor: true, hand: null });
    expect(p(ALI).caps).toContain('publish.audio');
    expect(p(ALI).caps).not.toContain('publish.video');
    expect(effectsOf(r, 'livekit.permissions')).toEqual([
      { kind: 'livekit.permissions', userId: ALI, sources: ['microphone'] },
    ]);
  });

  it('can include the camera', () => {
    ok(cmd(HOST, { type: 'floor.give', userId: ALI, video: true }));
    expect(p(ALI).caps).toEqual(expect.arrayContaining(['publish.audio', 'publish.video']));
  });

  it('taking the floor back removes the rights and stops the tracks', () => {
    ok(cmd(HOST, { type: 'floor.give', userId: ALI, video: true }));
    const r = ok(cmd(HOST, { type: 'floor.take', userId: ALI }));
    expect(p(ALI).floor).toBe(false);
    expect(p(ALI).caps).not.toContain('publish.audio');
    expect(effectsOf(r, 'livekit.mute')).toEqual([
      { kind: 'livekit.mute', userId: ALI, media: ['audio', 'video'] },
    ]);
  });

  it('revoking the microphone ends the floor', () => {
    ok(cmd(HOST, { type: 'floor.give', userId: ALI, video: false }));
    ok(cmd(HOST, { type: 'caps.revoke', userId: ALI, caps: ['publish.audio'] }));
    expect(p(ALI).floor).toBe(false);
  });

  it('is refused to students', () => {
    expect(refused(cmd(SARA, { type: 'floor.give', userId: ALI, video: false }))).toBe(
      'CAPABILITY_MISSING',
    );
  });
});

describe('capabilities and roles', () => {
  it('grants and revokes individual capabilities', () => {
    ok(cmd(HOST, { type: 'caps.grant', userId: ALI, caps: ['whiteboard.draw'] }));
    ok(cmd(HOST, { type: 'caps.revoke', userId: ALI, caps: ['chat.send'] }));
    expect(p(ALI).caps).toEqual(['whiteboard.draw', 'hand.raise']);
    expect(refused(cmd(ALI, { type: 'chat.send', text: 'سلام' }))).toBe('CAPABILITY_MISSING');
  });

  it('refuses to grant management rights individually', () => {
    expect(
      refused(cmd(HOST, { type: 'caps.grant', userId: ALI, caps: ['participants.manage'] })),
    ).toBe('VALIDATION_FAILED');
  });

  it('refuses to grant a capability the granter does not hold', () => {
    // Cohosts cannot raise hands, so they cannot hand that out either.
    expect(refused(cmd(COHOST, { type: 'caps.grant', userId: ALI, caps: ['hand.raise'] }))).toBe(
      'CAPABILITY_MISSING',
    );
  });

  it('refuses action on an equal or higher rank', () => {
    expect(refused(cmd(COHOST, { type: 'participant.mute', userId: HOST, source: 'audio' }))).toBe(
      'FORBIDDEN',
    );
    ok(join('usr_01J8ZB00000000000000000005', 'cohost'));
    expect(
      refused(
        cmd(COHOST, {
          type: 'caps.revoke',
          userId: 'usr_01J8ZB00000000000000000005',
          caps: ['chat.send'],
        }),
      ),
    ).toBe('FORBIDDEN');
  });

  it('only role holders assign roles, and a class keeps a host', () => {
    expect(refused(cmd(COHOST, { type: 'role.set', userId: ALI, role: 'presenter' }))).toBe(
      'CAPABILITY_MISSING',
    );
    expect(refused(cmd(HOST, { type: 'role.set', userId: HOST, role: 'participant' }))).toBe(
      'FORBIDDEN',
    );
    ok(cmd(HOST, { type: 'role.set', userId: COHOST, role: 'host' }));
    ok(cmd(HOST, { type: 'role.set', userId: HOST, role: 'cohost' }));
    expect(p(HOST).role).toBe('cohost');
  });

  it('starts a new role clean', () => {
    ok(cmd(HOST, { type: 'caps.revoke', userId: ALI, caps: ['chat.send'] }));
    ok(cmd(HOST, { type: 'role.set', userId: ALI, role: 'presenter' }));
    expect(p(ALI).revokes).toEqual([]);
    expect(p(ALI).caps).toContain('chat.send');
    expect(p(ALI).caps).toContain('publish.screen');
  });

  it('pushes new publish rights to the SFU when a policy opens them, and mutes when it closes', () => {
    const opened = ok(cmd(HOST, { type: 'policy.update', patch: { participantsCanUnmute: true } }));
    expect(
      effectsOf(opened, 'livekit.permissions')
        .map((e) => e.userId)
        .sort(),
    ).toEqual([ALI, SARA].sort());
    const closed = ok(
      cmd(HOST, { type: 'policy.update', patch: { participantsCanUnmute: false } }),
    );
    expect(effectsOf(closed, 'livekit.mute')).toHaveLength(2);
    expect(p(ALI).caps).not.toContain('publish.audio');
  });

  it('ignores a policy update that changes nothing', () => {
    expect(
      ok(cmd(HOST, { type: 'policy.update', patch: { participantsCanChat: true } })).events,
    ).toEqual([]);
  });
});

describe('moderation', () => {
  it('sends a mute notice only to the muted person', () => {
    const r = ok(cmd(HOST, { type: 'participant.mute', userId: ALI, source: 'audio' }));
    expect(r.events[0]!.audience).toEqual({ userId: ALI });
    expect(effectsOf(r, 'livekit.mute')).toEqual([
      { kind: 'livekit.mute', userId: ALI, media: ['audio'] },
    ]);
  });

  it('mute-all reaches everyone below the actor, not the host', () => {
    const r = ok(cmd(COHOST, { type: 'participant.muteAll' }));
    expect(
      effectsOf(r, 'livekit.mute')
        .map((e) => e.userId)
        .sort(),
    ).toEqual([ALI, SARA].sort());
  });

  it('removes a participant for good', () => {
    const r = ok(cmd(HOST, { type: 'participant.remove', userId: ALI, reason: 'بی‌نظمی' }));
    expect(room.participants.has(ALI)).toBe(false);
    expect(effectsOf(r, 'disconnect')[0]).toMatchObject({
      userId: ALI,
      closeCode: GATEWAY_CLOSE_CODES.removed,
      error: { code: 'REMOVED_FROM_CLASS' },
    });
    expect(effectsOf(r, 'livekit.remove')).toHaveLength(1);
    expect(refused(join(ALI, 'participant'))).toBe('REMOVED_FROM_CLASS');
  });
});

describe('chat', () => {
  it('stamps messages with a server id, name, role and time', () => {
    const r = ok(cmd(ALI, { type: 'chat.send', text: 'سوال دارم' }));
    expect(r.events[0]!.evt).toMatchObject({
      type: 'chat.message',
      message: { userId: ALI, role: 'participant', text: 'سوال دارم' },
    });
    expect(room.chat).toHaveLength(1);
  });

  it(`limits a person to ${CHAT_RATE.messages} messages per window`, () => {
    for (let i = 0; i < CHAT_RATE.messages; i++) ok(cmd(ALI, { type: 'chat.send', text: `${i}` }));
    expect(refused(cmd(ALI, { type: 'chat.send', text: 'x' }))).toBe('RATE_LIMITED');
    clock += CHAT_RATE.windowMs;
    ok(cmd(ALI, { type: 'chat.send', text: 'later' }));
  });

  it('lets people delete their own messages, and managers anyone’s', () => {
    ok(cmd(ALI, { type: 'chat.send', text: 'a' }));
    const id = room.chat[0]!.id;
    expect(refused(cmd(SARA, { type: 'chat.delete', messageId: id }))).toBe('CAPABILITY_MISSING');
    ok(cmd(COHOST, { type: 'chat.delete', messageId: id }));
    expect(room.chat).toHaveLength(0);
  });
});

describe('whiteboard', () => {
  it('refuses drawing without the capability, allows it once the policy opens', () => {
    expect(refused(cmd(ALI, { type: 'wb.add', item: stroke(W1) }))).toBe('CAPABILITY_MISSING');
    ok(cmd(HOST, { type: 'policy.update', patch: { participantsCanDraw: true } }));
    const r = ok(cmd(ALI, { type: 'wb.add', item: stroke(W1) }));
    expect(r.events[0]!.evt).toMatchObject({ type: 'wb.added', items: [{ id: W1, by: ALI }] });
  });

  it('refuses a reused item id', () => {
    ok(cmd(HOST, { type: 'wb.add', item: stroke(W1) }));
    expect(refused(cmd(HOST, { type: 'wb.add', item: stroke(W1) }))).toBe('VALIDATION_FAILED');
  });

  it('lets a drawer erase their own items but not other people’s', () => {
    ok(cmd(HOST, { type: 'policy.update', patch: { participantsCanDraw: true } }));
    ok(cmd(HOST, { type: 'wb.add', item: stroke(W1) }));
    ok(cmd(ALI, { type: 'wb.add', item: stroke(W2) }));
    expect(refused(cmd(ALI, { type: 'wb.remove', itemIds: [W1] }))).toBe('CAPABILITY_MISSING');
    ok(cmd(ALI, { type: 'wb.remove', itemIds: [W2] }));
    ok(cmd(HOST, { type: 'wb.remove', itemIds: [W1] }));
    expect(room.board.items.size).toBe(0);
  });

  it('undo restores exactly what was erased, whatever the client sends', () => {
    ok(cmd(HOST, { type: 'wb.add', item: stroke(W1) }));
    ok(cmd(HOST, { type: 'wb.remove', itemIds: [W1] }));
    const tampered = { ...stroke(W1), color: '#D32F2F' };
    ok(cmd(HOST, { type: 'wb.restore', items: [tampered] }));
    expect(room.board.items.get(W1)).toMatchObject({ color: '#1B1B1F', by: HOST });
  });

  it('refuses restoring someone else’s item without manage rights', () => {
    ok(cmd(HOST, { type: 'policy.update', patch: { participantsCanDraw: true } }));
    ok(cmd(HOST, { type: 'wb.add', item: stroke(W1) }));
    ok(cmd(HOST, { type: 'wb.remove', itemIds: [W1] }));
    expect(refused(cmd(ALI, { type: 'wb.restore', items: [stroke(W1)] }))).toBe(
      'CAPABILITY_MISSING',
    );
  });

  it('clears a page and can undo the clear', () => {
    ok(cmd(HOST, { type: 'wb.add', item: stroke(W1) }));
    ok(cmd(HOST, { type: 'wb.add', item: stroke(W2) }));
    ok(cmd(HOST, { type: 'wb.clear', pageId: PAGE }));
    expect(room.board.items.size).toBe(0);
    ok(cmd(HOST, { type: 'wb.restore', items: [stroke(W1), stroke(W2)] }));
    expect([...room.board.items.keys()]).toEqual([W1, W2]);
  });

  it('manages pages: add and select, keep the last page, move off a removed active page', () => {
    const P2 = 'wbp_01J8ZD00000000000000000002';
    ok(cmd(HOST, { type: 'wb.page.add', page: { id: P2, background: 'grid' }, select: true }));
    expect(room.board.activePageId).toBe(P2);
    ok(cmd(HOST, { type: 'wb.add', item: stroke(W1, P2) }));
    const r = ok(cmd(HOST, { type: 'wb.page.remove', pageId: P2 }));
    expect(r.events.map((e) => e.evt.type)).toEqual(['wb.page.selected', 'wb.page.removed']);
    expect(room.board.activePageId).toBe(PAGE);
    expect(room.board.items.size).toBe(0);
    expect(refused(cmd(HOST, { type: 'wb.page.remove', pageId: PAGE }))).toBe('VALIDATION_FAILED');
  });

  it('refuses page management to plain drawers', () => {
    ok(cmd(HOST, { type: 'policy.update', patch: { participantsCanDraw: true } }));
    expect(refused(cmd(ALI, { type: 'wb.clear', pageId: PAGE }))).toBe('CAPABILITY_MISSING');
  });
});

describe('capture reports', () => {
  it('alerts managers only and marks the participant', () => {
    const r = ok(
      cmd(ALI, {
        type: 'capture.report',
        capturing: true,
        signals: ['recorder_process'],
        detail: 'obs64.exe',
      }),
    );
    const alert = r.events.find((e) => e.evt.type === 'capture.alert')!;
    expect(alert.audience).toBe('managers');
    expect(alert.evt).toMatchObject({ userId: ALI, capturing: true, detail: 'obs64.exe' });
    expect(p(ALI).capturing).toBe(true);
    expect(effectsOf(r, 'audit')[0]!.audit.kind).toBe('capture.detected');
    expect(effectsOf(r, 'attendance')[0]).toMatchObject({ change: 'capture' });
  });

  it('shows the capturing flag to managers, never to other students', () => {
    ok(cmd(ALI, { type: 'capture.report', capturing: true, signals: ['os_recording'] }));
    const forSara = snapshotFor(room, SARA).participants.find((x) => x.userId === ALI)!;
    const forHost = snapshotFor(room, HOST).participants.find((x) => x.userId === ALI)!;
    expect(forSara.capturing).toBe(false);
    expect(forHost.capturing).toBe(true);
  });

  it('ignores a repeated report of the same state', () => {
    ok(cmd(ALI, { type: 'capture.report', capturing: true, signals: ['os_recording'] }));
    expect(
      ok(cmd(ALI, { type: 'capture.report', capturing: true, signals: ['os_recording'] })).events,
    ).toEqual([]);
  });

  it('alerts on a screenshot even without a capturing state', () => {
    const r = ok(cmd(ALI, { type: 'capture.report', capturing: false, signals: ['screenshot'] }));
    expect(r.events.map((e) => e.evt.type)).toEqual(['capture.alert']);
    expect(effectsOf(r, 'audit')[0]!.audit.kind).toBe('capture.screenshot');
  });

  it('records when capture stops', () => {
    ok(cmd(ALI, { type: 'capture.report', capturing: true, signals: ['os_recording'] }));
    const r = ok(cmd(ALI, { type: 'capture.report', capturing: false, signals: [] }));
    expect(p(ALI).capturing).toBe(false);
    expect(effectsOf(r, 'audit')[0]!.audit.kind).toBe('capture.cleared');
  });
});

describe('layout, recording and the end of class', () => {
  it('lets only layout.change holders change the stage', () => {
    expect(refused(cmd(ALI, { type: 'layout.apply', layout: LAYOUT_PRESETS.qa }))).toBe(
      'CAPABILITY_MISSING',
    );
    ok(cmd(COHOST, { type: 'layout.apply', layout: LAYOUT_PRESETS.qa }));
    expect(room.layout.id).toBe('qa');
  });

  it('records recording state changes', () => {
    ok(
      run({
        kind: 'recording',
        recording: { active: true, startedAt: new Date(clock).toISOString() },
      }),
    );
    expect(room.recording.active).toBe(true);
  });

  it('refuses everything once the class has ended', () => {
    ok(run({ kind: 'end', reason: 'host_ended' }));
    expect(room.ended).toBe(true);
    expect(refused(cmd(HOST, { type: 'chat.send', text: 'x' }))).toBe('CLASS_ENDED');
  });
});
