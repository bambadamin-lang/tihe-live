import { maskPhone } from '@tihe/contracts';
import type { Watermark } from '@tihe/contracts';

/**
 * Watermark parameters for one playback session.
 *
 * The purpose is attribution, not deterrence: nothing here stops a camera pointed at the screen,
 * but every frame it captures carries enough to identify the account. See
 * docs/08-threat-model.md — this is the mitigation for T3, the attacker we cannot block.
 *
 * Three decisions worth stating:
 *
 * 1. **The number is masked.** A full phone number burned into a video that then leaks is a privacy
 *    harm we would have caused ourselves. Masked digits plus the short account id are enough to
 *    identify one student from our own records, and not enough for a stranger to call them.
 * 2. **The seed is per session**, not per user. An attacker who records twice gets two different
 *    drift paths, so the mark cannot be averaged away across recordings or cropped out with one
 *    fixed rectangle.
 * 3. **The text is built server-side.** The client renders it but does not compose it, so a patched
 *    client cannot substitute someone else's identity.
 */
export function deriveWatermark(params: {
  phone: string;
  userId: string;
  seed: number;
}): Watermark {
  return {
    // e.g. "0912•••6789 · #7C3M" — the suffix is the tail of the ULID, short enough to read off a
    // blurry frame and unique enough to look up.
    text: `${maskPhone(params.phone)} · #${params.userId.slice(-4).toUpperCase()}`,
    opacity: 0.28,
    fontSize: 13,
    movement: 'drift',
    periodSeconds: 47,
    seed: params.seed,
  };
}

/**
 * Reverses a watermark string back to the account that produced it.
 *
 * This is the leak-investigation path: an admin reads the mark off a leaked video and gets the
 * student. Returns the components to match against, since the full number is never in the mark.
 */
export function parseWatermark(text: string): { maskedPhone: string; idSuffix: string } | null {
  const match = /^(\d{4}•+\d{4})\s·\s#([0-9A-Z]{4})$/.exec(text.trim());
  if (!match) return null;
  return { maskedPhone: match[1]!, idSuffix: match[2]! };
}

/** A session seed. Not security-critical — it only needs to differ between sessions. */
export function newWatermarkSeed(): number {
  return Math.floor(Math.random() * 2_147_483_647);
}
