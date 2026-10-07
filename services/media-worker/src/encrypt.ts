import { createCipheriv } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

import { segmentIv } from '@tihe/crypto';

/**
 * Segment encryption.
 *
 * AES-128-CTR, one keystream position per segment, IV derived from `(contentKeyId, sequence)` by
 * `segmentIv` in @tihe/crypto — the same function `secure-core` uses on the device. That shared
 * derivation is the whole reason a client can decrypt without being told an IV per segment.
 *
 * **The content key id must already exist** when this runs, because the IV depends on it. The
 * packager therefore creates the `content_keys` row before transcoding, not after.
 */

/**
 * Encrypts one segment, returning the ciphertext.
 *
 * Reads and returns buffers rather than streaming: a 6-second segment is a few megabytes, and a
 * whole-buffer round trip keeps the IV/keystream handling obvious. Streaming would be a worthwhile
 * change only for much longer segments.
 */
export async function encryptSegment(options: {
  dir: string;
  fileName: string;
  sequence: number;
  contentKey: Buffer;
  contentKeyId: string;
}): Promise<Buffer> {
  const plaintext = await readFile(join(options.dir, options.fileName));
  const iv = segmentIv(options.contentKeyId, options.sequence);

  const cipher = createCipheriv('aes-128-ctr', options.contentKey, iv);
  return Buffer.concat([cipher.update(plaintext), cipher.final()]);
}

/**
 * The sequence number for a segment file name.
 *
 * ffmpeg writes `seg-00000.ts`, and the number in that name *is* the sequence the IV derives from.
 * Parsing it rather than relying on directory order matters: `readdir` order is not guaranteed, and
 * an off-by-one here yields segments that decrypt to noise.
 */
export function sequenceOf(fileName: string): number {
  const match = /seg-(\d+)\.ts$/.exec(fileName);
  if (!match) throw new Error(`unexpected segment file name: ${fileName}`);
  return Number(match[1]);
}
