import { localPhone } from '../common.js';

/**
 * The short account id printed in every identity watermark, live and recorded.
 *
 * Five ASCII digits derived from the user id with FNV-1a, so the leak-lookup tool (M6) can map a
 * watermark read off a leaked frame back to candidate accounts by recomputing it — no lookup
 * table to keep in sync. Five digits collide across a large user base; the name and phone printed
 * beside it identify one account.
 *
 * ASCII, not Persian digits, because OCR on a re-encoded camera copy reads them far better.
 * The Dart implementation in tihe_classroom must return identical results; both are tested
 * against the same vectors.
 */
export function watermarkShortId(userId: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < userId.length; i++) {
    hash ^= userId.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return String(hash % 100000).padStart(5, '0');
}

/**
 * The live watermark, one row per line: the name, the full phone number beneath it, then the
 * short id — `علی کریمی\n09121234503\n#48213`. The client appends the current time to the last
 * row when it draws the mark. A row with nothing to show is left out.
 */
export function liveWatermarkText(
  who: { displayName: string | null; phone: string | null },
  userId: string,
): string {
  return [
    who.displayName?.trim() || null,
    who.phone ? localPhone(who.phone) : null,
    `#${watermarkShortId(userId)}`,
  ]
    .filter((row): row is string => row !== null)
    .join('\n');
}
