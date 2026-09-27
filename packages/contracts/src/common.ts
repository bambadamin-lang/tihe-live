import { z } from 'zod';

/**
 * Prefixed ULIDs. The prefix makes a mis-passed id obvious in a log line, which matters a
 * lot when four different id types flow through one playback request.
 */
export const ID_PREFIXES = {
  user: 'usr',
  device: 'dev',
  term: 'trm',
  course: 'crs',
  section: 'sec',
  video: 'vid',
  asset: 'ast',
  contentKey: 'ck',
  license: 'lic',
  download: 'dl',
  recording: 'rec',
  playbackSession: 'ps',
  chapter: 'chp',
  attachment: 'att',
  quiz: 'qz',
  note: 'nt',
  // Live classroom — see docs/11-live-classroom.md
  liveClass: 'cls',
  liveSession: 'ses',
  layout: 'lay',
  chatMessage: 'chm',
  boardItem: 'wbi',
  boardPage: 'wbp',
  liveAudit: 'lae',
} as const;

export type IdKind = keyof typeof ID_PREFIXES;

const ULID_BODY = '[0-9A-HJKMNP-TV-Z]{26}';

/** A zod schema for one specific id type, e.g. `id('video')` matches `vid_01J8Z...`. */
export const id = <K extends IdKind>(kind: K) =>
  z
    .string()
    .regex(
      new RegExp(`^${ID_PREFIXES[kind]}_${ULID_BODY}$`),
      `must be a ${kind} id (${ID_PREFIXES[kind]}_…)`,
    )
    .describe(`${kind} id`);

/**
 * Iranian mobile numbers in E.164. Stored this way, displayed as 09xxxxxxxxx.
 * Accepts the local forms on input and normalises, because users type all three.
 */
export const phoneSchema = z
  .string()
  .trim()
  .transform((raw) => {
    // Fold Persian and Arabic-Indic digits to ASCII — users paste these constantly.
    const ascii = raw
      .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
      .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660));
    const digits = ascii.replace(/[^\d+]/g, '');
    if (digits.startsWith('+98')) return digits;
    if (digits.startsWith('0098')) return `+${digits.slice(2)}`;
    if (digits.startsWith('98') && digits.length === 12) return `+${digits}`;
    if (digits.startsWith('09')) return `+98${digits.slice(1)}`;
    if (digits.startsWith('9') && digits.length === 10) return `+98${digits}`;
    return digits;
  })
  .pipe(z.string().regex(/^\+989\d{9}$/, 'must be a valid Iranian mobile number'));

/**
 * Masks a phone number for display and logging: +989123456789 → 0912•••6789.
 * Never log an unmasked number — see CLAUDE.md.
 */
export function maskPhone(e164: string): string {
  const local = e164.replace(/^\+98/, '0');
  if (local.length < 11) return '•'.repeat(local.length);
  return `${local.slice(0, 4)}•••${local.slice(-4)}`;
}

export const platformSchema = z.enum(['windows', 'android', 'ios', 'macos', 'linux']);
export type Platform = z.infer<typeof platformSchema>;

export const roleSchema = z.enum(['student', 'teacher', 'admin']);
export type Role = z.infer<typeof roleSchema>;

/** Cursor pagination. Offset pagination duplicates rows when the list shifts under you. */
export const paginationQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().optional(),
});
export type PaginationQuery = z.infer<typeof paginationQuerySchema>;

export const paginated = <T extends z.ZodTypeAny>(item: T) =>
  z.object({
    items: z.array(item),
    nextCursor: z.string().nullable(),
  });

/**
 * Stable, machine-readable error codes. The client switches on these, so a code is never
 * renamed once released — add a new one instead.
 */
export const ERROR_CODES = [
  'VALIDATION_FAILED',
  'UNAUTHENTICATED',
  'TOKEN_EXPIRED',
  'FORBIDDEN',
  'NOT_FOUND',
  'OTP_INVALID',
  'OTP_EXPIRED',
  'OTP_RATE_LIMITED',
  'DEVICE_LIMIT_REACHED',
  'DEVICE_REVOKED',
  'DEVICE_UNKNOWN',
  'NOT_ENROLLED',
  'LICENSE_MISSING',
  'LICENSE_EXPIRED',
  'LICENSE_REVOKED',
  'CONCURRENT_STREAM_LIMIT',
  'DOWNLOAD_NOT_ALLOWED',
  'VIDEO_NOT_READY',
  'CAPTURE_ENVIRONMENT_BLOCKED',
  'RATE_LIMITED',
  'INTERNAL',
  // Live classroom
  'CLASS_NOT_LIVE',
  'CLASS_ENDED',
  'CLASS_LOCKED',
  'CLASS_FULL',
  'CAPABILITY_MISSING',
  'REMOVED_FROM_CLASS',
  'JOINED_ELSEWHERE',
] as const;

export const errorCodeSchema = z.enum(ERROR_CODES);
export type ErrorCode = z.infer<typeof errorCodeSchema>;

/**
 * One error shape for every failure, so the client has one code path.
 *
 * `messageFa` is part of the contract on purpose: if the client had to map codes to Persian
 * strings itself, any code added after a release would render blank or in English on
 * already-installed apps.
 */
export const errorResponseSchema = z.object({
  error: z.object({
    code: errorCodeSchema,
    message: z.string(),
    messageFa: z.string(),
    details: z.record(z.unknown()).optional(),
    requestId: z.string(),
  }),
});
export type ErrorResponse = z.infer<typeof errorResponseSchema>;
