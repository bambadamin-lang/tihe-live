import { localPhone } from '../common.js';

/**
 * A short account id: five ASCII digits derived from the user id with FNV-1a, so the
 * leak-lookup tool (M6) can map an id read off a leaked frame back to candidate accounts by
 * recomputing it — no lookup table to keep in sync.
 *
 * The live watermark no longer prints it (it carries the whole phone number, which identifies
 * the account by itself); it names a user the directory does not know, as "کاربر 48213".
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
 * The live watermark, as the institute asked for it: the viewer's name, and under it their
 * whole phone number, `مریم احمدی\n09123456789`. No short id and no clock. The phone stays in
 * ASCII digits for OCR on a leaked copy; without a name the mark is the number alone.
 *
 * It names its owner in full, so it goes only to them, in their own join response.
 */
export function liveWatermarkText(displayName: string | null, phoneE164: string): string {
  const name = displayName?.trim();
  const phone = localPhone(phoneE164);
  return name ? `${name}\n${phone}` : phone;
}
