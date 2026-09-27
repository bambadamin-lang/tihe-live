import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

/**
 * Wrapping content keys with the Key Encryption Key.
 *
 * This is the layer that makes a stolen database useless: `content_keys.wrapped_key` holds only
 * ciphertext, and the KEK lives in the API's environment, never in Postgres. Either one alone
 * decrypts nothing (see docs/03-content-protection.md, layer 2).
 *
 * **There is exactly one definition of this format, here.** It previously existed twice — as a static
 * method on `PlaybackService` and inline in the seed script, with a comment admitting the duplication
 * — and the packager would have made three. A KEK format that differs by one byte between the writer
 * and the reader makes every video in the library permanently undecryptable, with no error until
 * someone tries to play one.
 *
 * Layout: `iv(12) || ciphertext || tag(16)`, AES-256-GCM.
 *
 * GCM rather than CBC so a corrupted or tampered row fails loudly, instead of yielding a plausible
 * 16 bytes that then decrypt video into noise.
 */

const IV_LEN = 12;
const TAG_LEN = 16;
const KEK_LEN = 32;
const CEK_LEN = 16;

function loadKek(kekBase64: string): Buffer {
  const kek = Buffer.from(kekBase64, 'base64');
  if (kek.length !== KEK_LEN) {
    throw new Error(`KEK must decode to ${KEK_LEN} bytes, got ${kek.length}`);
  }
  return kek;
}

/** Wraps a content key for storage. Used by the packager and the seed. */
export function wrapContentKeyWithKek(cek: Buffer, kekBase64: string): string {
  if (cek.length !== CEK_LEN) {
    throw new Error(`content key must be ${CEK_LEN} bytes, got ${cek.length}`);
  }

  const kek = loadKek(kekBase64);
  const iv = randomBytes(IV_LEN);
  const cipher = createCipheriv('aes-256-gcm', kek, iv);
  const ciphertext = Buffer.concat([cipher.update(cek), cipher.final()]);
  const wrapped = Buffer.concat([iv, ciphertext, cipher.getAuthTag()]).toString('base64');

  kek.fill(0);
  return wrapped;
}

/**
 * Unwraps a stored content key. Used only when minting a playback session or a download manifest,
 * and the plaintext is re-wrapped for one device immediately afterwards — it is never returned to a
 * client and never stored.
 */
export function unwrapContentKeyWithKek(wrapped: string, kekBase64: string): Buffer {
  const kek = loadKek(kekBase64);
  const blob = Buffer.from(wrapped, 'base64');

  if (blob.length < IV_LEN + TAG_LEN + 1) {
    throw new Error('wrapped content key is truncated');
  }

  const iv = blob.subarray(0, IV_LEN);
  const tag = blob.subarray(blob.length - TAG_LEN);
  const ciphertext = blob.subarray(IV_LEN, blob.length - TAG_LEN);

  const decipher = createDecipheriv('aes-256-gcm', kek, iv);
  decipher.setAuthTag(tag);
  const cek = Buffer.concat([decipher.update(ciphertext), decipher.final()]);

  kek.fill(0);
  return cek;
}
