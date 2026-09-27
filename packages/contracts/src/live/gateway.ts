import { z } from 'zod';
import { id } from '../common.js';
import { errorCodeSchema } from '../common.js';
import { captureSignalSchema } from './capture.js';
import { layoutSchema } from './layout.js';
import {
  assignableRoleSchema,
  capabilitySchema,
  classRoleSchema,
  roomPolicySchema,
} from './roles.js';
import {
  BOARD_BACKGROUNDS,
  boardItemInputSchema,
  boardItemSchema,
  boardPageSchema,
  boardProgressSchema,
  boardStateSchema,
} from './whiteboard.js';

/**
 * The classroom gateway protocol — the WebSocket at `/v1/live/ws`. See ADR-0010.
 *
 * - Client commands are acknowledged (`ack`) or refused (`nack`, with a Persian message).
 * - Accepted commands become sequenced events (`evt`). Every client applies the same events
 *   in the same order, so every stage agrees.
 * - Ephemeral traffic (whiteboard previews, laser pointer) is relayed as `eph` and never stored.
 * - On reconnect the client sends its `lastSeq`; the server replays what it missed or, if that
 *   is too far back, sends a fresh snapshot.
 */

export const MAX_CHAT_LENGTH = 1000;
/** Chat messages kept in a snapshot. Older ones are in the audit store, not the stage. */
export const SNAPSHOT_CHAT_LIMIT = 200;

/** WebSocket close codes the client must handle rather than silently reconnect. */
export const GATEWAY_CLOSE_CODES = {
  unauthenticated: 4001,
  protocolError: 4002,
  removed: 4003,
  joinedElsewhere: 4009,
  classEnded: 4010,
} as const;

// ─── State ────────────────────────────────────────────────────────────────────

export const handSchema = z.object({
  /** Server sequence number when raised: the queue order. Never client time. */
  raisedSeq: z.number().int().nonnegative(),
  raisedAt: z.string().datetime(),
});

export const participantStateSchema = z.object({
  userId: id('user'),
  name: z.string(),
  role: classRoleSchema,
  /** Effective capabilities: role preset ∪ policy ∪ grants − revokes. Computed by the server. */
  caps: z.array(capabilitySchema),
  grants: z.array(capabilitySchema),
  revokes: z.array(capabilitySchema),
  hand: handSchema.nullable(),
  /** Holds the floor: speaking through an accepted raised hand. */
  floor: z.boolean(),
  online: z.boolean(),
  /**
   * Whether this participant is currently detected capturing the screen. Only sent to people
   * with `participants.manage`; everyone else always sees `false`.
   */
  capturing: z.boolean(),
  joinedAt: z.string().datetime(),
});
export type ParticipantState = z.infer<typeof participantStateSchema>;

export const chatMessageSchema = z.object({
  id: id('chatMessage'),
  userId: id('user'),
  name: z.string(),
  role: classRoleSchema,
  text: z.string().min(1).max(MAX_CHAT_LENGTH),
  at: z.string().datetime(),
});
export type ChatMessage = z.infer<typeof chatMessageSchema>;

export const recordingStateSchema = z.object({
  active: z.boolean(),
  startedAt: z.string().datetime().nullable(),
});
export type RecordingState = z.infer<typeof recordingStateSchema>;

export const classroomSnapshotSchema = z.object({
  sessionId: id('liveSession'),
  classId: id('liveClass'),
  title: z.string(),
  startedAt: z.string().datetime(),
  policy: roomPolicySchema,
  layout: layoutSchema,
  participants: z.array(participantStateSchema),
  chat: z.array(chatMessageSchema).max(SNAPSHOT_CHAT_LIMIT),
  board: boardStateSchema,
  recording: recordingStateSchema,
});
export type ClassroomSnapshot = z.infer<typeof classroomSnapshotSchema>;

// ─── Commands (client → server) ───────────────────────────────────────────────

const target = { userId: id('user') };

export const classroomCommandSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('hand.raise') }),
  /** Without `userId`: lower your own hand. With it: a manager lowers someone else's. */
  z.object({ type: z.literal('hand.lower'), userId: id('user').optional() }),
  z.object({ type: z.literal('hand.lowerAll') }),
  /** Accept a raised hand: temporary microphone (and camera if `video`) for that person. */
  z.object({ type: z.literal('floor.give'), ...target, video: z.boolean() }),
  z.object({ type: z.literal('floor.take'), ...target }),

  z.object({ type: z.literal('caps.grant'), ...target, caps: z.array(capabilitySchema).min(1) }),
  z.object({ type: z.literal('caps.revoke'), ...target, caps: z.array(capabilitySchema).min(1) }),
  z.object({ type: z.literal('caps.reset'), ...target }),
  z.object({ type: z.literal('role.set'), ...target, role: assignableRoleSchema }),
  z.object({ type: z.literal('policy.update'), patch: roomPolicySchema.partial() }),

  z.object({
    type: z.literal('participant.mute'),
    ...target,
    source: z.enum(['audio', 'video', 'screen']),
  }),
  /** Mute the microphone of everyone ranked below you. */
  z.object({ type: z.literal('participant.muteAll') }),
  z.object({
    type: z.literal('participant.remove'),
    ...target,
    reason: z.string().max(200).optional(),
  }),

  z.object({ type: z.literal('layout.apply'), layout: layoutSchema }),

  z.object({ type: z.literal('chat.send'), text: z.string().trim().min(1).max(MAX_CHAT_LENGTH) }),
  z.object({ type: z.literal('chat.delete'), messageId: id('chatMessage') }),

  z.object({ type: z.literal('wb.add'), item: boardItemInputSchema }),
  z.object({ type: z.literal('wb.remove'), itemIds: z.array(id('boardItem')).min(1).max(500) }),
  /** Undo of a removal: puts items back exactly as they were. */
  z.object({ type: z.literal('wb.restore'), items: z.array(boardItemInputSchema).min(1).max(500) }),
  z.object({ type: z.literal('wb.clear'), pageId: id('boardPage') }),
  z.object({
    type: z.literal('wb.page.add'),
    page: boardPageSchema,
    select: z.boolean(),
  }),
  z.object({ type: z.literal('wb.page.select'), pageId: id('boardPage') }),
  z.object({ type: z.literal('wb.page.remove'), pageId: id('boardPage') }),

  z.object({
    type: z.literal('capture.report'),
    capturing: z.boolean(),
    signals: z.array(captureSignalSchema),
    /** e.g. the recorder process name. Shown to the host, stored in the audit log. */
    detail: z.string().max(120).optional(),
  }),
]);
export type ClassroomCommand = z.infer<typeof classroomCommandSchema>;
export type ClassroomCommandType = ClassroomCommand['type'];

// ─── Events (server → client) ─────────────────────────────────────────────────

export const classroomEventSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('participant.joined'), participant: participantStateSchema }),
  /** Any change to one participant: role, capabilities, hand, floor, presence, capture. */
  z.object({ type: z.literal('participant.updated'), participant: participantStateSchema }),
  z.object({ type: z.literal('participant.left'), userId: id('user') }),
  z.object({
    type: z.literal('participant.removed'),
    userId: id('user'),
    reason: z.string().nullable(),
  }),
  z.object({ type: z.literal('policy.updated'), policy: roomPolicySchema }),
  z.object({ type: z.literal('layout.applied'), layout: layoutSchema, by: id('user') }),

  z.object({ type: z.literal('chat.message'), message: chatMessageSchema }),
  z.object({ type: z.literal('chat.deleted'), messageId: id('chatMessage') }),

  z.object({ type: z.literal('wb.added'), items: z.array(boardItemSchema).min(1) }),
  z.object({ type: z.literal('wb.removed'), itemIds: z.array(id('boardItem')).min(1) }),
  z.object({ type: z.literal('wb.cleared'), pageId: id('boardPage') }),
  z.object({ type: z.literal('wb.page.added'), page: boardPageSchema }),
  z.object({ type: z.literal('wb.page.selected'), pageId: id('boardPage') }),
  z.object({ type: z.literal('wb.page.removed'), pageId: id('boardPage') }),

  /** Sent only to people with `participants.manage`. */
  z.object({
    type: z.literal('capture.alert'),
    userId: id('user'),
    name: z.string(),
    capturing: z.boolean(),
    signals: z.array(captureSignalSchema),
    detail: z.string().nullable(),
  }),
  /** Sent only to the person whose media a manager stopped, so their app can explain why. */
  z.object({
    type: z.literal('media.muted'),
    userId: id('user'),
    source: z.enum(['audio', 'video', 'screen']),
    by: id('user'),
  }),
  z.object({ type: z.literal('recording.changed'), recording: recordingStateSchema }),
  z.object({ type: z.literal('class.ended'), reason: z.enum(['host_ended', 'timeout']) }),
]);
export type ClassroomEvent = z.infer<typeof classroomEventSchema>;
export type ClassroomEventType = ClassroomEvent['type'];

export const sequencedEventSchema = z.object({
  t: z.literal('evt'),
  seq: z.number().int().nonnegative(),
  at: z.string().datetime(),
  evt: classroomEventSchema,
});
export type SequencedEvent = z.infer<typeof sequencedEventSchema>;

// ─── Envelopes ────────────────────────────────────────────────────────────────

export const clientMessageSchema = z.discriminatedUnion('t', [
  /** First message on every connection. The ticket comes from the join response. */
  z.object({
    t: z.literal('hello'),
    ticket: z.string().min(16),
    lastSeq: z.number().int().nonnegative().nullable(),
  }),
  z.object({ t: z.literal('cmd'), id: z.string().min(1).max(40), cmd: classroomCommandSchema }),
  z.object({ t: z.literal('eph'), eph: boardProgressSchema }),
  z.object({ t: z.literal('ping') }),
]);
export type ClientMessage = z.infer<typeof clientMessageSchema>;

export const gatewayErrorSchema = z.object({
  code: errorCodeSchema,
  message: z.string(),
  messageFa: z.string(),
});
export type GatewayError = z.infer<typeof gatewayErrorSchema>;

export const serverMessageSchema = z.discriminatedUnion('t', [
  z.object({
    t: z.literal('welcome'),
    you: z.object({ userId: id('user'), role: classRoleSchema }),
    /** The latest sequence number, whether or not a snapshot is attached. */
    seq: z.number().int().nonnegative(),
    /** Present on first connect, or when `lastSeq` is too old to replay. */
    snapshot: classroomSnapshotSchema.nullable(),
    /** Present when the missed events could be replayed instead. */
    replay: z.array(sequencedEventSchema).nullable(),
  }),
  sequencedEventSchema,
  z.object({ t: z.literal('eph'), from: id('user'), eph: boardProgressSchema }),
  z.object({ t: z.literal('ack'), id: z.string() }),
  z.object({ t: z.literal('nack'), id: z.string(), error: gatewayErrorSchema }),
  z.object({ t: z.literal('pong') }),
  /** Sent right before the server closes the socket with one of GATEWAY_CLOSE_CODES. */
  z.object({ t: z.literal('bye'), error: gatewayErrorSchema }),
]);
export type ServerMessage = z.infer<typeof serverMessageSchema>;

/** A fresh page, as the board starts with and `wb.page.add` sends. */
export const DEFAULT_PAGE_BACKGROUND: (typeof BOARD_BACKGROUNDS)[number] = 'plain';
