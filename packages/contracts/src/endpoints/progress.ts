import { z } from 'zod';
import { id } from '../common.js';

export const progressSchema = z.object({
  videoId: id('video'),
  positionMs: z.number().int().nonnegative(),
  completed: z.boolean(),
  updatedAt: z.string().datetime(),
});
export type Progress = z.infer<typeof progressSchema>;

export const updateProgressBodySchema = z.object({
  positionMs: z.number().int().nonnegative(),
  completed: z.boolean().optional(),
});
export type UpdateProgressBody = z.infer<typeof updateProgressBodySchema>;

export const watchEventKindSchema = z.enum(['start', 'heartbeat', 'seek', 'pause', 'complete']);
export type WatchEventKind = z.infer<typeof watchEventKindSchema>;

export const watchEventSchema = z.object({
  videoId: id('video'),
  deviceId: id('device'),
  event: watchEventKindSchema,
  positionMs: z.number().int().nonnegative(),
  /**
   * When the event happened on the client, not when it arrived. A device that watched three
   * lectures offline posts them all at once on reconnect, and the real timing is what makes
   * the statistics meaningful. The server clamps absurd values rather than trusting blindly.
   */
  occurredAt: z.string().datetime(),
  /** True when the event was recorded with no network, for offline-usage reporting. */
  offline: z.boolean().default(false),
});
export type WatchEvent = z.infer<typeof watchEventSchema>;

/** Batched because offline sync is the normal case, not the exception. */
export const watchEventsBodySchema = z.object({
  events: z.array(watchEventSchema).min(1).max(500),
});
export type WatchEventsBody = z.infer<typeof watchEventsBodySchema>;

export const watchEventsResponseSchema = z.object({
  accepted: z.number().int().nonnegative(),
  rejected: z.number().int().nonnegative(),
  /** Returned so a client whose licence was revoked mid-flight finds out on its next sync. */
  revocationEpoch: z.number().int().nonnegative(),
});
