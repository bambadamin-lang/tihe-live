import { z } from 'zod';
import { id, platformSchema } from '../common.js';

/**
 * Parameters for the on-screen identity watermark.
 *
 * Sent per playback session rather than baked into the app so the institute can tune
 * visibility without shipping a new build, and so `seed` differs per session — which is what
 * stops an attacker from cropping the mark out of a whole recording or averaging it away
 * across frames.
 *
 * Rendered in the native view layer, never as a Dart widget. See docs/03-content-protection.md.
 */
export const watermarkSchema = z.object({
  /**
   * For playback, already masked, e.g. "0912•••6789 · #48213": the API never sends a full
   * number. In a live class, the owner's own full number, e.g. "09121234567 · #48213"
   * (docs/11 §9).
   */
  text: z.string(),
  opacity: z.number().min(0.05).max(1),
  fontSize: z.number().int().min(8).max(48),
  movement: z.enum(['static', 'drift', 'corners']),
  /** Seconds for one full movement cycle. */
  periodSeconds: z.number().int().positive(),
  /** Per-session seed for the drift path. */
  seed: z.number().int(),
});
export type Watermark = z.infer<typeof watermarkSchema>;

export const encryptionSchema = z.object({
  scheme: z.literal('AES-128-CTR'),
  ivMode: z.literal('per-segment-sequence'),
  keyId: id('contentKey'),
});
export type Encryption = z.infer<typeof encryptionSchema>;

/**
 * What the server returns to start protected playback.
 *
 * `wrappedKey` is the content key sealed to this device's X25519 public key. Only
 * `packages/secure-core` can open it, using a private key that never leaves the OS keystore —
 * so this payload is useless on any other device, and useless to Dart code on this one.
 */
export const playbackSessionSchema = z.object({
  sessionId: id('playbackSession'),
  videoId: id('video'),
  manifestUrl: z.string().url(),
  segmentBaseUrl: z.string().url(),
  wrappedKey: z.string().base64(),
  encryption: encryptionSchema,
  watermark: watermarkSchema,
  /** Capture blocking is a server decision (course policy), not a client preference. */
  blockCapture: z.boolean(),
  expiresAt: z.string().datetime(),
  heartbeatIntervalSeconds: z.number().int().positive(),
  /** Client compares against its stored epoch; a lower value means its licence is stale. */
  revocationEpoch: z.number().int().nonnegative(),
});
export type PlaybackSession = z.infer<typeof playbackSessionSchema>;

/**
 * The licence blob, signed with Ed25519 and verified offline by the client against a public
 * key embedded in the binary. These are the exact fields covered by the signature — adding one
 * is a breaking change for installed apps, so the `v` field exists to version it.
 */
export const licensePayloadSchema = z.object({
  v: z.literal(1),
  licenseId: id('license'),
  userId: id('user'),
  deviceIds: z.array(id('device')),
  scope: z.object({
    courseIds: z.array(id('course')),
    videoIds: z.array(id('video')),
  }),
  notBefore: z.string().datetime(),
  notAfter: z.string().datetime(),
  maxDevices: z.number().int().positive(),
  maxConcurrentStreams: z.number().int().positive(),
  offlineWindowDays: z.number().int().positive(),
  revocationEpoch: z.number().int().nonnegative(),
  issuedAt: z.string().datetime(),
  /**
   * The server's clock at issue time. Stored sealed on the device: a system clock reading
   * earlier than this means the device is lying about the time, and playback stops.
   */
  serverTime: z.string().datetime(),
});
export type LicensePayload = z.infer<typeof licensePayloadSchema>;

export const licenseSchema = z.object({
  payload: licensePayloadSchema,
  /** Base64 Ed25519 signature over the canonical CBOR encoding of `payload`. */
  signature: z.string().base64(),
  /** The exact bytes the client verifies. Stored server-side so we can always show what was issued. */
  blob: z.string().base64(),
  revokedAt: z.string().datetime().nullable(),
  revokedReason: z.string().nullable(),
});
export type License = z.infer<typeof licenseSchema>;

export const downloadStateSchema = z.enum([
  'queued',
  'downloading',
  'complete',
  'expired',
  'deleted',
]);
export type DownloadState = z.infer<typeof downloadStateSchema>;

/** One segment of an offline download, with the presigned URL to fetch its ciphertext. */
export const downloadSegmentSchema = z.object({
  rendition: z.string(),
  seq: z.number().int().nonnegative(),
  url: z.string().url(),
  byteSize: z.number().int(),
  /** Per-segment IV, so the client can decrypt without parsing the manifest. */
  iv: z.string().base64(),
});
export type DownloadSegment = z.infer<typeof downloadSegmentSchema>;

/**
 * Everything needed to build a `.tihex` file on the device.
 *
 * The header is assembled and signed server-side; the client appends ciphertext as it
 * downloads. That ordering is deliberate: the signature covers `notAfter` and `deviceId`, so a
 * student cannot extend their own expiry or retarget the file at another device.
 */
export const downloadManifestSchema = z.object({
  downloadId: id('download'),
  videoId: id('video'),
  deviceId: id('device'),
  licenseId: id('license'),
  /** Signed CBOR header for the .tihex container, base64. */
  containerHeader: z.string().base64(),
  wrappedKey: z.string().base64(),
  encryption: encryptionSchema,
  segments: z.array(downloadSegmentSchema),
  totalBytes: z.number().int(),
  expiresAt: z.string().datetime(),
  /** Presigned segment URLs expire; the client re-requests this manifest to resume. */
  urlsExpireAt: z.string().datetime(),
});
export type DownloadManifest = z.infer<typeof downloadManifestSchema>;

export const downloadSchema = z.object({
  id: id('download'),
  videoId: id('video'),
  videoTitle: z.string(),
  deviceId: id('device'),
  devicePlatform: platformSchema,
  state: downloadStateSchema,
  bytesDownloaded: z.number().int().nonnegative(),
  totalBytes: z.number().int().nonnegative(),
  expiresAt: z.string().datetime().nullable(),
  createdAt: z.string().datetime(),
});
export type Download = z.infer<typeof downloadSchema>;
