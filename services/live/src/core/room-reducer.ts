import {
  ERROR_CATALOG,
  GATEWAY_CLOSE_CODES,
  MAX_ITEMS_PER_PAGE,
  MAX_PAGES,
  type BoardItem,
  type Capability,
  type CaptureSignal,
  type ClassRole,
  type ClassroomCommand,
  type ClassroomEvent,
  type ErrorCode,
  type GatewayError,
  type ParticipantState,
  type RecordingState,
  type SequencedEvent,
} from '@tihe/contracts';
import {
  FLOOR_CAPABILITIES,
  GRANTABLE_CAPABILITIES,
  effectiveCapabilities,
  lostMedia,
  mediaSources,
  outranks,
  sameCapabilities,
  type MediaKind,
  type MediaTrackSource,
} from './capabilities.js';
import type { IdFactory } from './ids.js';
import { applyEvent, type RoomState } from './room-state.js';

/**
 * The classroom rules: given the room and one input, decide which events happen and which side
 * effects follow — or refuse, with a Persian message. Pure apart from mutating `state` through
 * `applyEvent`, so every rule is testable without a socket, Redis or LiveKit.
 */

export type Audience = 'all' | 'managers' | { userId: string };

export type AuditKind =
  | 'capture.detected'
  | 'capture.cleared'
  | 'capture.screenshot'
  | 'capture.removed'
  | 'capture.block_failed'
  | 'participant.removed'
  | 'participant.muted'
  | 'caps.changed'
  | 'role.changed'
  | 'floor.given'
  | 'floor.taken'
  | 'policy.changed'
  | 'recording.changed'
  | 'class.ended';

export interface AuditEntry {
  kind: AuditKind;
  actorId: string | null;
  targetId: string | null;
  detail: Record<string, unknown>;
}

export type Effect =
  /** Push the publish rights the SFU enforces. */
  | { kind: 'livekit.permissions'; userId: string; sources: MediaTrackSource[] }
  /** Stop tracks that were published: a mute, or a right that was just taken away. */
  | { kind: 'livekit.mute'; userId: string; media: MediaKind[] }
  | { kind: 'livekit.remove'; userId: string }
  | { kind: 'disconnect'; userId: string; closeCode: number; error: GatewayError }
  | { kind: 'audit'; audit: AuditEntry }
  | {
      kind: 'attendance';
      change: 'join' | 'leave' | 'capture';
      userId: string;
      name: string;
      role: ClassRole;
      at: string;
    };

export type RoomInput =
  | { kind: 'command'; actorId: string; cmd: ClassroomCommand }
  | { kind: 'join'; userId: string; name: string; role: ClassRole }
  | { kind: 'leave'; userId: string }
  | { kind: 'recording'; recording: RecordingState }
  | { kind: 'end'; reason: 'host_ended' | 'timeout' };

export interface RoomContext {
  now: Date;
  newId: IdFactory;
}

export type AudiencedEvent = SequencedEvent & { audience: Audience };

export type ExecuteResult =
  { ok: true; events: AudiencedEvent[]; effects: Effect[] } | { ok: false; error: GatewayError };

interface Out {
  evt: ClassroomEvent;
  audience: Audience;
}
type Decision = { ok: true; events: Out[]; effects: Effect[] } | { ok: false; error: GatewayError };

export function gatewayError(code: ErrorCode, message: string): GatewayError {
  return { code, message, messageFa: ERROR_CATALOG[code].messageFa };
}

const fail = (code: ErrorCode, message: string): Decision => ({
  ok: false,
  error: gatewayError(code, message),
});
const done = (events: Out[] = [], effects: Effect[] = []): Decision => ({
  ok: true,
  events,
  effects,
});
const toAll = (evt: ClassroomEvent): Out => ({ evt, audience: 'all' });
const updated = (participant: ParticipantState): Out =>
  toAll({ type: 'participant.updated', participant });
const audit = (entry: AuditEntry): Effect => ({ kind: 'audit', audit: entry });

/** Chat flood control: at most this many messages per window, per person. */
export const CHAT_RATE = { messages: 5, windowMs: 10_000 };
const chatTimes = new WeakMap<RoomState, Map<string, number[]>>();

export function execute(state: RoomState, input: RoomInput, ctx: RoomContext): ExecuteResult {
  if (state.ended) return { ok: false, error: gatewayError('CLASS_ENDED', 'class has ended') };

  const decision = decide(state, input, ctx);
  if (!decision.ok) return decision;

  const before = new Map([...state.participants].map(([id, p]) => [id, p.caps]));
  const at = ctx.now.toISOString();
  const events: AudiencedEvent[] = [];
  for (const out of decision.events) {
    const sequenced: SequencedEvent = { t: 'evt', seq: state.seq + 1, at, evt: out.evt };
    applyEvent(state, sequenced);
    events.push({ ...sequenced, audience: out.audience });
  }
  return { ok: true, events, effects: [...decision.effects, ...mediaEffects(before, state)] };
}

/**
 * Whenever someone's publish rights change — a grant, a policy toggle, a role change, the floor —
 * the SFU is told, and tracks they may no longer publish are stopped. Derived here once, from
 * the before/after capabilities, so no command handler can forget to do it.
 */
function mediaEffects(before: Map<string, Capability[]>, state: RoomState): Effect[] {
  const effects: Effect[] = [];
  for (const [userId, p] of state.participants) {
    const prev = before.get(userId);
    if (!prev || sameCapabilities(prev, p.caps)) continue;
    const prevSources = mediaSources(prev);
    const nextSources = mediaSources(p.caps);
    if (prevSources.join() !== nextSources.join()) {
      effects.push({ kind: 'livekit.permissions', userId, sources: nextSources });
    }
    const lost = lostMedia(prev, p.caps);
    if (lost.length > 0 && p.online) effects.push({ kind: 'livekit.mute', userId, media: lost });
  }
  return effects;
}

/** A participant with some fields changed and capabilities recomputed from the result. */
function recompute(state: RoomState, p: ParticipantState, patch: Partial<ParticipantState>) {
  const next = { ...p, ...patch };
  next.caps = effectiveCapabilities(next.role, state.policy, next.grants, next.revokes);
  if (!next.caps.includes('hand.raise')) next.hand = null;
  return next;
}

const union = (a: readonly Capability[], b: readonly Capability[]) => [...new Set([...a, ...b])];
const minus = (a: readonly Capability[], b: readonly Capability[]) =>
  a.filter((c) => !b.includes(c));

function decide(state: RoomState, input: RoomInput, ctx: RoomContext): Decision {
  const at = ctx.now.toISOString();
  switch (input.kind) {
    case 'join':
      return decideJoin(state, input, at);
    case 'leave': {
      const p = state.participants.get(input.userId);
      if (!p || !p.online) return done();
      const next = recompute(state, p, {
        online: false,
        hand: null,
        floor: false,
        capturing: false,
        grants: p.floor ? minus(p.grants, FLOOR_CAPABILITIES) : p.grants,
      });
      return done(
        [updated(next)],
        [{ kind: 'attendance', change: 'leave', userId: p.userId, name: p.name, role: p.role, at }],
      );
    }
    case 'recording':
      return done(
        [toAll({ type: 'recording.changed', recording: input.recording })],
        [
          audit({
            kind: 'recording.changed',
            actorId: null,
            targetId: null,
            detail: { ...input.recording },
          }),
        ],
      );
    case 'end':
      return done(
        [toAll({ type: 'class.ended', reason: input.reason })],
        [
          audit({
            kind: 'class.ended',
            actorId: null,
            targetId: null,
            detail: { reason: input.reason },
          }),
        ],
      );
    case 'command':
      return decideCommand(state, input.actorId, input.cmd, ctx);
  }
}

function decideJoin(
  state: RoomState,
  input: { userId: string; name: string; role: ClassRole },
  at: string,
): Decision {
  if (state.removed.has(input.userId)) {
    return fail('REMOVED_FROM_CLASS', 'removed from this session');
  }
  const attendance: Effect = {
    kind: 'attendance',
    change: 'join',
    userId: input.userId,
    name: input.name,
    role: input.role,
    at,
  };
  const existing = state.participants.get(input.userId);
  if (existing) {
    // A rejoin keeps what happened in class — a promotion, a grant — rather than the role the
    // ticket was minted with.
    return done([updated({ ...existing, name: input.name, online: true })], [attendance]);
  }
  const participant: ParticipantState = {
    userId: input.userId,
    name: input.name,
    role: input.role,
    caps: effectiveCapabilities(input.role, state.policy, [], []),
    grants: [],
    revokes: [],
    hand: null,
    floor: false,
    online: true,
    capturing: false,
    joinedAt: at,
  };
  return done([toAll({ type: 'participant.joined', participant })], [attendance]);
}

function decideCommand(
  state: RoomState,
  actorId: string,
  cmd: ClassroomCommand,
  ctx: RoomContext,
): Decision {
  const actor = state.participants.get(actorId);
  if (!actor || !actor.online) return fail('FORBIDDEN', 'not in this class');
  if (actor.role === 'recorder') return fail('FORBIDDEN', 'the recorder cannot act');
  const at = ctx.now.toISOString();

  const lacks = (cap: Capability) => !actor.caps.includes(cap);
  const missing = (cap: Capability) => fail('CAPABILITY_MISSING', `missing capability ${cap}`);

  /** A participant the actor may act on, or the reason they may not. */
  const target = (userId: string): ParticipantState | Decision => {
    const t = state.participants.get(userId);
    if (!t) return fail('NOT_FOUND', `no participant ${userId}`);
    if (!outranks(actor.role, t.role)) {
      return fail('FORBIDDEN', 'cannot act on someone of equal or higher rank');
    }
    return t;
  };
  const isDecision = (x: ParticipantState | Decision): x is Decision => 'ok' in x;

  /** Rule 2: nobody hands out, or takes away, a capability they do not hold themselves. */
  const checkDelegable = (caps: readonly Capability[]): Decision | null => {
    for (const cap of caps) {
      if (!GRANTABLE_CAPABILITIES.includes(cap)) {
        return fail('VALIDATION_FAILED', `${cap} comes with a role and cannot be granted alone`);
      }
      if (lacks(cap)) return missing(cap);
    }
    return null;
  };

  switch (cmd.type) {
    // ─── Hands and the floor ───────────────────────────────────────────────
    case 'hand.raise': {
      if (lacks('hand.raise')) return missing('hand.raise');
      if (actor.hand) return done();
      return done([updated({ ...actor, hand: { raisedSeq: state.seq + 1, raisedAt: at } })]);
    }
    case 'hand.lower': {
      if (!cmd.userId || cmd.userId === actorId) {
        return actor.hand ? done([updated({ ...actor, hand: null })]) : done();
      }
      if (lacks('participants.manage')) return missing('participants.manage');
      const t = target(cmd.userId);
      if (isDecision(t)) return t;
      return t.hand ? done([updated({ ...t, hand: null })]) : done();
    }
    case 'hand.lowerAll': {
      if (lacks('participants.manage')) return missing('participants.manage');
      const lowered = [...state.participants.values()]
        .filter((p) => p.hand && (p.userId === actorId || outranks(actor.role, p.role)))
        .map((p) => updated({ ...p, hand: null }));
      return done(lowered);
    }
    case 'floor.give': {
      if (lacks('participants.manage')) return missing('participants.manage');
      const t = target(cmd.userId);
      if (isDecision(t)) return t;
      const caps: Capability[] = cmd.video ? ['publish.audio', 'publish.video'] : ['publish.audio'];
      const refused = checkDelegable(caps);
      if (refused) return refused;
      const next = recompute(state, t, {
        grants: union(t.grants, caps),
        revokes: minus(t.revokes, caps),
        floor: true,
        hand: null,
      });
      return done(
        [updated(next)],
        [audit({ kind: 'floor.given', actorId, targetId: t.userId, detail: { video: cmd.video } })],
      );
    }
    case 'floor.take': {
      if (lacks('participants.manage')) return missing('participants.manage');
      const t = target(cmd.userId);
      if (isDecision(t)) return t;
      if (!t.floor) return done();
      const next = recompute(state, t, {
        grants: minus(t.grants, FLOOR_CAPABILITIES),
        floor: false,
      });
      return done(
        [updated(next)],
        [audit({ kind: 'floor.taken', actorId, targetId: t.userId, detail: {} })],
      );
    }

    // ─── Capabilities, roles, policy ───────────────────────────────────────
    case 'caps.grant':
    case 'caps.revoke': {
      if (lacks('participants.manage')) return missing('participants.manage');
      const t = target(cmd.userId);
      if (isDecision(t)) return t;
      const refused = checkDelegable(cmd.caps);
      if (refused) return refused;
      const granting = cmd.type === 'caps.grant';
      const grants = granting ? union(t.grants, cmd.caps) : minus(t.grants, cmd.caps);
      const revokes = granting ? minus(t.revokes, cmd.caps) : union(t.revokes, cmd.caps);
      const floor = t.floor && !(!granting && cmd.caps.includes('publish.audio'));
      if (sameCapabilities(grants, t.grants) && sameCapabilities(revokes, t.revokes)) return done();
      const next = recompute(state, t, { grants, revokes, floor });
      return done(
        [updated(next)],
        [
          audit({
            kind: 'caps.changed',
            actorId,
            targetId: t.userId,
            detail: { [granting ? 'granted' : 'revoked']: cmd.caps },
          }),
        ],
      );
    }
    case 'caps.reset': {
      if (lacks('participants.manage')) return missing('participants.manage');
      const t = target(cmd.userId);
      if (isDecision(t)) return t;
      const next = recompute(state, t, { grants: [], revokes: [], floor: false });
      return done(
        [updated(next)],
        [audit({ kind: 'caps.changed', actorId, targetId: t.userId, detail: { reset: true } })],
      );
    }
    case 'role.set': {
      if (lacks('roles.assign')) return missing('roles.assign');
      const t = state.participants.get(cmd.userId);
      if (!t) return fail('NOT_FOUND', `no participant ${cmd.userId}`);
      if (t.role === cmd.role) return done();
      if (t.role === 'recorder') return fail('FORBIDDEN', 'the recorder has no role to change');
      if (t.role === 'host') {
        const hosts = [...state.participants.values()].filter((p) => p.role === 'host').length;
        if (hosts < 2) return fail('FORBIDDEN', 'a class must keep at least one host');
      }
      // A new role starts clean: grants made under the old role would otherwise leak into it.
      const next = recompute(state, t, {
        role: cmd.role,
        grants: [],
        revokes: [],
        floor: false,
      });
      return done(
        [updated(next)],
        [
          audit({
            kind: 'role.changed',
            actorId,
            targetId: t.userId,
            detail: { from: t.role, to: cmd.role },
          }),
        ],
      );
    }
    case 'policy.update': {
      if (lacks('participants.manage')) return missing('participants.manage');
      const policy = { ...state.policy, ...cmd.patch };
      if (JSON.stringify(policy) === JSON.stringify(state.policy)) return done();
      const events: Out[] = [toAll({ type: 'policy.updated', policy })];
      const nextState = { ...state, policy };
      for (const p of state.participants.values()) {
        const next = recompute(nextState, p, {});
        if (!sameCapabilities(next.caps, p.caps) || next.hand !== p.hand)
          events.push(updated(next));
      }
      return done(events, [
        audit({ kind: 'policy.changed', actorId, targetId: null, detail: { patch: cmd.patch } }),
      ]);
    }

    // ─── Moderation ────────────────────────────────────────────────────────
    case 'participant.mute': {
      if (lacks('participants.manage')) return missing('participants.manage');
      const t = target(cmd.userId);
      if (isDecision(t)) return t;
      return done(
        [
          {
            evt: { type: 'media.muted', userId: t.userId, source: cmd.source, by: actorId },
            audience: { userId: t.userId },
          },
        ],
        [
          { kind: 'livekit.mute', userId: t.userId, media: [cmd.source] },
          audit({
            kind: 'participant.muted',
            actorId,
            targetId: t.userId,
            detail: { source: cmd.source },
          }),
        ],
      );
    }
    case 'participant.muteAll': {
      if (lacks('participants.manage')) return missing('participants.manage');
      const muted = [...state.participants.values()].filter(
        (p) => p.online && outranks(actor.role, p.role),
      );
      const events = muted.map((p): Out => ({
        evt: { type: 'media.muted', userId: p.userId, source: 'audio', by: actorId },
        audience: { userId: p.userId },
      }));
      const effects = muted.map((p): Effect => ({
        kind: 'livekit.mute',
        userId: p.userId,
        media: ['audio'],
      }));
      return done(events, effects);
    }
    case 'participant.remove': {
      if (lacks('participants.manage')) return missing('participants.manage');
      const t = target(cmd.userId);
      if (isDecision(t)) return t;
      const reason = cmd.reason ?? null;
      return done(
        [toAll({ type: 'participant.removed', userId: t.userId, reason })],
        [
          { kind: 'livekit.remove', userId: t.userId },
          {
            kind: 'disconnect',
            userId: t.userId,
            closeCode: GATEWAY_CLOSE_CODES.removed,
            error: gatewayError('REMOVED_FROM_CLASS', 'removed by a host'),
          },
          { kind: 'attendance', change: 'leave', userId: t.userId, name: t.name, role: t.role, at },
          audit({ kind: 'participant.removed', actorId, targetId: t.userId, detail: { reason } }),
        ],
      );
    }

    // ─── Layout and chat ───────────────────────────────────────────────────
    case 'layout.apply':
      if (lacks('layout.change')) return missing('layout.change');
      return done([toAll({ type: 'layout.applied', layout: cmd.layout, by: actorId })]);

    case 'chat.send': {
      if (lacks('chat.send')) return missing('chat.send');
      const now = ctx.now.getTime();
      const perRoom = chatTimes.get(state) ?? new Map<string, number[]>();
      chatTimes.set(state, perRoom);
      const recent = (perRoom.get(actorId) ?? []).filter((t) => now - t < CHAT_RATE.windowMs);
      if (recent.length >= CHAT_RATE.messages) {
        return fail('RATE_LIMITED', 'too many chat messages');
      }
      perRoom.set(actorId, [...recent, now]);
      return done([
        toAll({
          type: 'chat.message',
          message: {
            id: ctx.newId('chatMessage'),
            userId: actorId,
            name: actor.name,
            role: actor.role,
            text: cmd.text,
            at,
          },
        }),
      ]);
    }
    case 'chat.delete': {
      const message = state.chat.find((m) => m.id === cmd.messageId);
      if (!message) return fail('NOT_FOUND', 'no such message');
      if (message.userId !== actorId && lacks('participants.manage')) {
        return missing('participants.manage');
      }
      return done([toAll({ type: 'chat.deleted', messageId: cmd.messageId })]);
    }

    // ─── Whiteboard ────────────────────────────────────────────────────────
    case 'wb.add': {
      if (lacks('whiteboard.draw')) return missing('whiteboard.draw');
      const item = cmd.item;
      if (!state.board.pages.some((p) => p.id === item.pageId)) {
        return fail('NOT_FOUND', 'no such page');
      }
      if (state.board.items.has(item.id) || state.tombstones.has(item.id)) {
        return fail('VALIDATION_FAILED', 'item id already used');
      }
      const onPage = [...state.board.items.values()].filter((i) => i.pageId === item.pageId).length;
      if (onPage >= MAX_ITEMS_PER_PAGE) return fail('VALIDATION_FAILED', 'page is full');
      const stored = { ...item, by: actorId, seq: state.seq + 1 } as BoardItem;
      return done([toAll({ type: 'wb.added', items: [stored] })]);
    }
    case 'wb.remove': {
      if (lacks('whiteboard.draw')) return missing('whiteboard.draw');
      const found = cmd.itemIds
        .map((id) => state.board.items.get(id))
        .filter((i): i is BoardItem => i !== undefined);
      if (found.length === 0) return done();
      if (lacks('whiteboard.manage') && found.some((i) => i.by !== actorId)) {
        return missing('whiteboard.manage');
      }
      return done([toAll({ type: 'wb.removed', itemIds: found.map((i) => i.id) })]);
    }
    case 'wb.restore': {
      if (lacks('whiteboard.draw')) return missing('whiteboard.draw');
      const restored: BoardItem[] = [];
      for (const input of cmd.items) {
        if (state.board.items.has(input.id)) continue;
        // Restore what was actually erased, not whatever the client claims it was.
        const tomb = state.tombstones.get(input.id);
        const base = tomb ?? ({ ...input, by: actorId } as BoardItem);
        if (!state.board.pages.some((p) => p.id === base.pageId)) continue;
        if (base.by !== actorId && lacks('whiteboard.manage')) return missing('whiteboard.manage');
        restored.push({ ...base, seq: state.seq + 1 });
      }
      if (restored.length === 0) return done();
      return done([toAll({ type: 'wb.added', items: restored })]);
    }
    case 'wb.clear': {
      if (lacks('whiteboard.manage')) return missing('whiteboard.manage');
      if (!state.board.pages.some((p) => p.id === cmd.pageId))
        return fail('NOT_FOUND', 'no such page');
      const any = [...state.board.items.values()].some((i) => i.pageId === cmd.pageId);
      return any ? done([toAll({ type: 'wb.cleared', pageId: cmd.pageId })]) : done();
    }
    case 'wb.page.add': {
      if (lacks('whiteboard.manage')) return missing('whiteboard.manage');
      if (state.board.pages.length >= MAX_PAGES) return fail('VALIDATION_FAILED', 'too many pages');
      if (state.board.pages.some((p) => p.id === cmd.page.id)) {
        return fail('VALIDATION_FAILED', 'page id already used');
      }
      const events: Out[] = [toAll({ type: 'wb.page.added', page: cmd.page })];
      if (cmd.select) events.push(toAll({ type: 'wb.page.selected', pageId: cmd.page.id }));
      return done(events);
    }
    case 'wb.page.select': {
      if (lacks('whiteboard.manage')) return missing('whiteboard.manage');
      if (!state.board.pages.some((p) => p.id === cmd.pageId))
        return fail('NOT_FOUND', 'no such page');
      if (state.board.activePageId === cmd.pageId) return done();
      return done([toAll({ type: 'wb.page.selected', pageId: cmd.pageId })]);
    }
    case 'wb.page.remove': {
      if (lacks('whiteboard.manage')) return missing('whiteboard.manage');
      const index = state.board.pages.findIndex((p) => p.id === cmd.pageId);
      if (index < 0) return fail('NOT_FOUND', 'no such page');
      if (state.board.pages.length === 1) return fail('VALIDATION_FAILED', 'the last page stays');
      const events: Out[] = [];
      if (state.board.activePageId === cmd.pageId) {
        const neighbour = state.board.pages[index > 0 ? index - 1 : 1]!;
        events.push(toAll({ type: 'wb.page.selected', pageId: neighbour.id }));
      }
      events.push(toAll({ type: 'wb.page.removed', pageId: cmd.pageId }));
      return done(events);
    }

    // ─── Capture protection ────────────────────────────────────────────────
    case 'capture.report':
      return decideCapture(state, actor, cmd.capturing, cmd.signals, cmd.detail ?? null, at);
  }
}

/**
 * A client says it is (or no longer is) being recorded. Its own app has already censored the
 * class; here the host is told and the attempt is written down. A screenshot, or the OS
 * refusing to block capture, is an instant: it alerts even though the participant was never
 * in a "capturing" state.
 */
function decideCapture(
  state: RoomState,
  actor: ParticipantState,
  capturing: boolean,
  signals: CaptureSignal[],
  detail: string | null,
  at: string,
): Decision {
  const screenshot = signals.includes('screenshot');
  const blockFailed = signals.includes('block_failed');
  const removed = signals.includes('removed_for_recording');
  if (capturing === actor.capturing && !screenshot && !blockFailed && !removed) return done();

  const events: Out[] = [];
  if (capturing !== actor.capturing) events.push(updated({ ...actor, capturing }));
  events.push({
    evt: {
      type: 'capture.alert',
      userId: actor.userId,
      name: actor.name,
      capturing,
      signals,
      detail,
    },
    audience: 'managers',
  });

  const kind: AuditKind = removed
    ? 'capture.removed'
    : capturing
    ? 'capture.detected'
    : screenshot
      ? 'capture.screenshot'
      : blockFailed
        ? 'capture.block_failed'
        : 'capture.cleared';
  const effects: Effect[] = [
    audit({ kind, actorId: actor.userId, targetId: actor.userId, detail: { signals, detail } }),
  ];
  if (capturing || screenshot) {
    effects.push({
      kind: 'attendance',
      change: 'capture',
      userId: actor.userId,
      name: actor.name,
      role: actor.role,
      at,
    });
  }
  return done(events, effects);
}
