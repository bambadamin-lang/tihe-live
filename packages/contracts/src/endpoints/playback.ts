import { z } from 'zod';
import { id } from '../common.js';
import {
  downloadManifestSchema,
  downloadSchema,
  playbackSessionSchema,
} from '../entities/protection.js';

export const startPlaybackBodySchema = z.object({
  deviceId: id('device'),
  /** Preferred rendition label; the server may return a different one it has available. */
  rendition: z.string().optional(),
  /**
   * What the client observed about its own environment. The server decides what to do with
   * it — a client that omits or fakes this is handled by server-side policy, so this is a
   * signal, never the enforcement point.
   */
  environment: z
    .object({
      screenRecorderDetected: z.boolean(),
      virtualDisplayDetected: z.boolean(),
      rootedOrJailbroken: z.boolean(),
      emulator: z.boolean(),
      debuggerAttached: z.boolean(),
    })
    .optional(),
});
export type StartPlaybackBody = z.infer<typeof startPlaybackBodySchema>;

export const startPlaybackResponseSchema = playbackSessionSchema;

export const heartbeatBodySchema = z.object({
  positionMs: z.number().int().nonnegative(),
});

export const heartbeatResponseSchema = z.object({
  ok: z.literal(true),
  expiresAt: z.string().datetime(),
  /** The lever that makes revocation land within one heartbeat interval. */
  revocationEpoch: z.number().int().nonnegative(),
  /** Server instruction to stop immediately — licence revoked, or session superseded. */
  stop: z.boolean(),
  stopReason: z.string().nullable(),
});

export const createDownloadBodySchema = z.object({
  videoId: id('video'),
  deviceId: id('device'),
  rendition: z.string().optional(),
});
export type CreateDownloadBody = z.infer<typeof createDownloadBodySchema>;

export const createDownloadResponseSchema = downloadManifestSchema;

export const downloadsResponseSchema = z.object({
  items: z.array(downloadSchema),
});
