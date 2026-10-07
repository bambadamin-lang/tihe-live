import { createDecipheriv, randomBytes } from 'node:crypto';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { segmentIv } from '@tihe/crypto';

import { encryptSegment, sequenceOf } from './encrypt.js';

describe('sequenceOf', () => {
  it('reads the sequence from the file name', () => {
    // Parsed rather than taken from directory order: readdir order is not guaranteed, and an
    // off-by-one here produces segments that decrypt to noise.
    expect(sequenceOf('seg-00000.ts')).toBe(0);
    expect(sequenceOf('seg-00042.ts')).toBe(42);
    expect(sequenceOf('seg-01234.ts')).toBe(1234);
  });

  it('rejects an unexpected name rather than guessing', () => {
    expect(() => sequenceOf('segment1.ts')).toThrow();
    expect(() => sequenceOf('seg-.ts')).toThrow();
  });
});

describe('encryptSegment', () => {
  let dir: string;

  beforeAll(async () => {
    dir = await mkdtemp(join(tmpdir(), 'enc-test-'));
  });

  afterAll(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  const contentKey = Buffer.from('0123456789abcdef', 'utf8');
  const contentKeyId = 'ck_01J8ZQK5T9XVWR3M2N4P6H8B7C';

  it('encrypts with the IV derived from the key id and sequence', async () => {
    const plaintext = randomBytes(4096);
    await writeFile(join(dir, 'seg-00007.ts'), plaintext);

    const ciphertext = await encryptSegment({
      dir,
      fileName: 'seg-00007.ts',
      sequence: 7,
      contentKey,
      contentKeyId,
    });

    expect(ciphertext.equals(plaintext)).toBe(false);

    // Decryptable with the IV a client derives independently — which is the only way the device can
    // decrypt without being sent an IV per segment.
    const decipher = createDecipheriv('aes-128-ctr', contentKey, segmentIv(contentKeyId, 7));
    const recovered = Buffer.concat([decipher.update(ciphertext), decipher.final()]);

    expect(recovered.equals(plaintext)).toBe(true);
  });

  it('produces different ciphertext for the same bytes at different sequences', async () => {
    // AES-CTR under a reused (key, IV) leaks the XOR of the two plaintexts. Two identical segments
    // must not encrypt identically.
    const plaintext = Buffer.alloc(1024, 0x47);
    await writeFile(join(dir, 'seg-00001.ts'), plaintext);
    await writeFile(join(dir, 'seg-00002.ts'), plaintext);

    const first = await encryptSegment({
      dir,
      fileName: 'seg-00001.ts',
      sequence: 1,
      contentKey,
      contentKeyId,
    });
    const second = await encryptSegment({
      dir,
      fileName: 'seg-00002.ts',
      sequence: 2,
      contentKey,
      contentKeyId,
    });

    expect(first.equals(second)).toBe(false);
  });

  it('does not decrypt under a different key id', async () => {
    // The key id is part of the IV, so a segment from one video cannot be replayed as another's even
    // if the content key leaked.
    const plaintext = randomBytes(512);
    await writeFile(join(dir, 'seg-00003.ts'), plaintext);

    const ciphertext = await encryptSegment({
      dir,
      fileName: 'seg-00003.ts',
      sequence: 3,
      contentKey,
      contentKeyId,
    });

    const decipher = createDecipheriv('aes-128-ctr', contentKey, segmentIv('ck_other', 3));
    const recovered = Buffer.concat([decipher.update(ciphertext), decipher.final()]);

    expect(recovered.equals(plaintext)).toBe(false);
  });

  it('preserves length, as a stream cipher must', async () => {
    // CTR adds no padding. A length change would break the byte ranges the container index records.
    const plaintext = randomBytes(1_000);
    await writeFile(join(dir, 'seg-00004.ts'), plaintext);

    const ciphertext = await encryptSegment({
      dir,
      fileName: 'seg-00004.ts',
      sequence: 4,
      contentKey,
      contentKeyId,
    });

    expect(ciphertext.length).toBe(plaintext.length);
  });
});
