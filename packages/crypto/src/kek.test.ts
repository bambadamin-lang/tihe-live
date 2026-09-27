import { randomBytes } from 'node:crypto';
import { describe, expect, it } from 'vitest';

import { unwrapContentKeyWithKek, wrapContentKeyWithKek } from './kek.js';

const kek = randomBytes(32).toString('base64');

describe('KEK wrapping', () => {
  it('round trips a content key', () => {
    const cek = randomBytes(16);
    expect(unwrapContentKeyWithKek(wrapContentKeyWithKek(cek, kek), kek)).toEqual(cek);
  });

  it('produces a different blob each time for the same key', () => {
    // A fresh IV per wrap: reusing one across videos would leak their XOR.
    const cek = randomBytes(16);
    expect(wrapContentKeyWithKek(cek, kek)).not.toBe(wrapContentKeyWithKek(cek, kek));
  });

  it('does not unwrap under a different KEK', () => {
    // The property the whole layer exists for: a database dump without the KEK is inert.
    const wrapped = wrapContentKeyWithKek(randomBytes(16), kek);
    const other = randomBytes(32).toString('base64');

    expect(() => unwrapContentKeyWithKek(wrapped, other)).toThrow();
  });

  it('rejects a tampered blob rather than returning plausible bytes', () => {
    // This is why GCM and not CBC: CBC would hand back 16 wrong bytes that then decrypt video into
    // noise, with nothing to indicate the key was wrong.
    const wrapped = wrapContentKeyWithKek(randomBytes(16), kek);
    const blob = Buffer.from(wrapped, 'base64');
    blob[blob.length - 1] ^= 0xff;

    expect(() => unwrapContentKeyWithKek(blob.toString('base64'), kek)).toThrow();
  });

  it('rejects a truncated blob', () => {
    expect(() => unwrapContentKeyWithKek(Buffer.alloc(8).toString('base64'), kek)).toThrow(
      /truncated/,
    );
  });

  it('rejects a KEK of the wrong length', () => {
    // Catches a half-pasted value in .env at the first call rather than at the first playback.
    expect(() => wrapContentKeyWithKek(randomBytes(16), 'c2hvcnQ=')).toThrow(/32 bytes/);
  });

  it('rejects a content key of the wrong length', () => {
    expect(() => wrapContentKeyWithKek(randomBytes(32), kek)).toThrow(/16 bytes/);
  });
});
