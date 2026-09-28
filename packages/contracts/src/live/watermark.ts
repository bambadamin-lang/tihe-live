/**
 * The short account id printed in every identity watermark, live and recorded.
 *
 * Five ASCII digits derived from the user id with FNV-1a, so the leak-lookup tool (M6) can map a
 * watermark read off a leaked frame back to candidate accounts by recomputing it — no lookup
 * table to keep in sync. Five digits collide across a large user base; the phone number beside
 * them identifies the account on its own.
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
 * `09121234567 · #48213`: the owner's full number, as they would write it, and the short id.
 * The client appends the current time when it draws the mark.
 *
 * The number is not masked (docs/11 §9): a student who films the class films their own full
 * number, so a leaked copy names its source without a lookup, and the mark itself deters.
 */
export function liveWatermarkText(phoneE164: string, userId: string): string {
  const local = phoneE164.replace(/^\+98/, '0');
  return `${local} · #${watermarkShortId(userId)}`;
}
