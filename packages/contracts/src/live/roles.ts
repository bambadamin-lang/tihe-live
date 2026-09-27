import { z } from 'zod';

/**
 * Roles inside one live class. Distinct from the account role (`student`/`teacher`/`admin`):
 * a student can be made presenter for ten minutes, and a teacher can sit in someone else's
 * class as a participant. See docs/11-live-classroom.md §3.
 */
export const CLASS_ROLES = ['host', 'cohost', 'presenter', 'participant', 'recorder'] as const;
export const classRoleSchema = z.enum(CLASS_ROLES);
export type ClassRole = z.infer<typeof classRoleSchema>;

/** `recorder` is Egress. Nobody can be assigned it. */
export const assignableRoleSchema = z.enum(['host', 'cohost', 'presenter', 'participant']);
export type AssignableRole = z.infer<typeof assignableRoleSchema>;

/** Higher outranks lower. You can only act on someone below you. */
export const ROLE_RANK: Readonly<Record<ClassRole, number>> = {
  recorder: 0,
  participant: 1,
  presenter: 2,
  cohost: 3,
  host: 4,
};

export const CAPABILITIES = [
  'publish.audio',
  'publish.video',
  'publish.screen',
  'whiteboard.draw',
  'whiteboard.manage',
  'chat.send',
  'hand.raise',
  'participants.manage',
  'roles.assign',
  'layout.change',
  'recording.control',
  'class.end',
] as const;
export const capabilitySchema = z.enum(CAPABILITIES);
export type Capability = z.infer<typeof capabilitySchema>;

/**
 * What each role can do before the room policy and per-user grants are applied. Participants
 * start with nothing: everything they can do comes from the policy, so the host controls it.
 */
export const ROLE_PRESETS: Readonly<Record<ClassRole, readonly Capability[]>> = {
  host: CAPABILITIES.filter((c) => c !== 'hand.raise'),
  cohost: [
    'publish.audio',
    'publish.video',
    'publish.screen',
    'whiteboard.draw',
    'whiteboard.manage',
    'chat.send',
    'participants.manage',
    'layout.change',
  ],
  presenter: [
    'publish.audio',
    'publish.video',
    'publish.screen',
    'whiteboard.draw',
    'whiteboard.manage',
    'chat.send',
    'hand.raise',
  ],
  participant: [],
  recorder: [],
};

/** Host-editable toggles. They apply to the `participant` role only. */
export const roomPolicySchema = z.object({
  participantsCanUnmute: z.boolean(),
  participantsCanStartVideo: z.boolean(),
  participantsCanShareScreen: z.boolean(),
  participantsCanDraw: z.boolean(),
  participantsCanChat: z.boolean(),
  handRaiseEnabled: z.boolean(),
  /** No new joins below cohost. People already in the room stay. */
  locked: z.boolean(),
});
export type RoomPolicy = z.infer<typeof roomPolicySchema>;

export const DEFAULT_ROOM_POLICY: Readonly<RoomPolicy> = {
  participantsCanUnmute: false,
  participantsCanStartVideo: false,
  participantsCanShareScreen: false,
  participantsCanDraw: false,
  participantsCanChat: true,
  handRaiseEnabled: true,
  locked: false,
};

/** Which capability each policy toggle hands to participants. `locked` grants nothing. */
export const POLICY_CAPABILITY: Readonly<Record<Exclude<keyof RoomPolicy, 'locked'>, Capability>> =
  {
    participantsCanUnmute: 'publish.audio',
    participantsCanStartVideo: 'publish.video',
    participantsCanShareScreen: 'publish.screen',
    participantsCanDraw: 'whiteboard.draw',
    participantsCanChat: 'chat.send',
    handRaiseEnabled: 'hand.raise',
  };
