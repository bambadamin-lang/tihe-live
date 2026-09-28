import { z } from 'zod';

/**
 * LiveKit Egress webhook payloads. This is the trigger for the entire video pipeline —
 * see docs/06-recording-pipeline.md for the full contract with the live-classroom service.
 *
 * Fields we do not use are not modelled: LiveKit adds keys over time, and a strict schema
 * here would reject a payload that is otherwise perfectly usable.
 */
export const egressFileResultSchema = z.object({
  filename: z.string(),
  location: z.string(),
  size: z.number().int().nonnegative().optional(),
  /** Nanoseconds, as LiveKit reports it. */
  duration: z.number().int().nonnegative().optional(),
});

export const egressInfoSchema = z.object({
  egressId: z.string(),
  roomName: z.string(),
  status: z.string(),
  startedAt: z.number().optional(),
  endedAt: z.number().optional(),
  error: z.string().optional(),
  fileResults: z.array(egressFileResultSchema).default([]),
});
export type EgressInfo = z.infer<typeof egressInfoSchema>;

export const livekitWebhookSchema = z
  .object({
    event: z.string(),
    egressInfo: egressInfoSchema.optional(),
    room: z.object({ name: z.string(), sid: z.string().optional() }).optional(),
    id: z.string().optional(),
    createdAt: z.number().optional(),
  })
  .passthrough();
export type LivekitWebhook = z.infer<typeof livekitWebhookSchema>;

/**
 * `metadata.json`, written by services/live into the raw recording prefix.
 *
 * `courseId` is the one field the pipeline cannot work without: it decides who may see the
 * resulting video. Without it the recording goes to `needs_attention` for manual filing
 * rather than risk publishing to the wrong audience.
 */
export const recordingMetadataSchema = z.object({
  classId: z.string(),
  sessionId: z.string(),
  courseId: z.string(),
  sectionId: z.string().nullish(),
  title: z.string(),
  teacherId: z.string().nullish(),
  scheduledStartAt: z.string().datetime().nullish(),
  actualStartAt: z.string().datetime().nullish(),
  actualEndAt: z.string().datetime().nullish(),
  participantCount: z.number().int().nonnegative().nullish(),
  livekitRoom: z.string().nullish(),
  egressIds: z.array(z.string()).default([]),
});
export type RecordingMetadata = z.infer<typeof recordingMetadataSchema>;

export const recordingStatusSchema = z.enum([
  'pending',
  'ingesting',
  'packaging',
  'ready',
  'failed',
  'needs_attention',
]);
export type RecordingStatus = z.infer<typeof recordingStatusSchema>;
