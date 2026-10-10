import { z } from 'zod';
import { id, roleSchema } from '../common.js';
import { watermarkSchema } from '../entities/protection.js';
import { capturePolicySchema } from './capture.js';
import { recordingStateSchema } from './gateway.js';
import { layoutPresetKeySchema, podSchema } from './layout.js';
import { classRoleSchema, roomPolicySchema } from './roles.js';

/**
 * REST surface of services/live, under `/v1/live`. See docs/11-live-classroom.md and
 * ADR-0012. Errors use the shared envelope in common.ts.
 */

export const classSettingsSchema = z.object({
  /** Start recording as soon as the host starts the session. On by default: a class that was
   *  not recorded never reaches the library. */
  autoRecord: z.boolean(),
  defaultLayout: layoutPresetKeySchema,
  policy: roomPolicySchema,
  maxParticipants: z.number().int().min(2).max(500),
});
export type ClassSettings = z.infer<typeof classSettingsSchema>;

export const liveClassSchema = z.object({
  id: id('liveClass'),
  courseId: id('course'),
  sectionId: id('section').nullable(),
  title: z.string(),
  description: z.string().nullable(),
  teacherId: id('user'),
  scheduledStartAt: z.string().datetime().nullable(),
  durationMinutes: z.number().int().positive(),
  settings: classSettingsSchema,
  /** The session currently live, if any — what the "join" button opens. */
  liveSessionId: id('liveSession').nullable(),
  createdAt: z.string().datetime(),
});
export type LiveClass = z.infer<typeof liveClassSchema>;

export const createClassBodySchema = z.object({
  courseId: id('course'),
  sectionId: id('section').optional(),
  title: z.string().trim().min(1).max(200),
  description: z.string().max(2000).optional(),
  scheduledStartAt: z.string().datetime().optional(),
  durationMinutes: z.number().int().min(15).max(480).default(90),
  settings: classSettingsSchema.partial().optional(),
});
export type CreateClassBody = z.infer<typeof createClassBodySchema>;

export const updateClassBodySchema = createClassBodySchema.omit({ courseId: true }).partial();
export type UpdateClassBody = z.infer<typeof updateClassBodySchema>;

export const listClassesQuerySchema = z.object({
  courseId: id('course').optional(),
});

export const liveSessionStatusSchema = z.enum(['live', 'ended']);

export const liveSessionSchema = z.object({
  id: id('liveSession'),
  classId: id('liveClass'),
  status: liveSessionStatusSchema,
  startedAt: z.string().datetime(),
  endedAt: z.string().datetime().nullable(),
  recording: recordingStateSchema,
});
export type LiveSession = z.infer<typeof liveSessionSchema>;

/**
 * Everything a client needs to enter a class. Minted per user per session, after the
 * enrollment check.
 *
 * `watermark.text` carries this user's own name and full phone number. It goes to its owner
 * only — never into LiveKit metadata, which every participant can read.
 */
export const joinResponseSchema = z.object({
  session: liveSessionSchema,
  classTitle: z.string(),
  you: z.object({ userId: id('user'), name: z.string(), role: classRoleSchema }),
  livekit: z.object({ url: z.string(), token: z.string() }),
  gateway: z.object({
    url: z.string(),
    ticket: z.string(),
    ticketExpiresAt: z.string().datetime(),
  }),
  watermark: watermarkSchema,
  capturePolicy: capturePolicySchema,
});
export type JoinResponse = z.infer<typeof joinResponseSchema>;

export const savedLayoutSchema = z.object({
  id: id('layout'),
  name: z.string().min(1).max(64),
  pods: z.array(podSchema),
  createdAt: z.string().datetime(),
});
export type SavedLayout = z.infer<typeof savedLayoutSchema>;

export const saveLayoutBodySchema = z.object({
  name: z.string().trim().min(1).max(64),
  pods: z.array(podSchema).min(1),
});
export type SaveLayoutBody = z.infer<typeof saveLayoutBodySchema>;

export const attendanceEntrySchema = z.object({
  userId: id('user'),
  name: z.string(),
  role: classRoleSchema,
  firstJoinedAt: z.string().datetime(),
  lastLeftAt: z.string().datetime().nullable(),
  /** Summed over reconnects, so a flaky connection does not inflate or erase attendance. */
  secondsPresent: z.number().int().nonnegative(),
  captureAttempts: z.number().int().nonnegative(),
});
export type AttendanceEntry = z.infer<typeof attendanceEntrySchema>;

/**
 * Claims in the access token services/api issues and services/live verifies (ADR-0012).
 * `iss` and `aud` are checked, so a token minted for another purpose is refused.
 */
export const ACCESS_TOKEN_ISSUER = 'tihe-api';
export const ACCESS_TOKEN_AUDIENCE = 'tihe';

export const accessTokenClaimsSchema = z.object({
  sub: id('user'),
  role: roleSchema,
  did: id('device'),
  iss: z.literal(ACCESS_TOKEN_ISSUER),
  aud: z.union([z.literal(ACCESS_TOKEN_AUDIENCE), z.array(z.string()).nonempty()]),
  iat: z.number().int(),
  exp: z.number().int(),
});
export type AccessTokenClaims = z.infer<typeof accessTokenClaimsSchema>;
