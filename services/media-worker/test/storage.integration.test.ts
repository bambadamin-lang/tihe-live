import { randomBytes } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { Env } from '../src/config.js';
import { CONTENT_TYPES, Storage, vodKeys } from '../src/storage.js';

/**
 * Exercises the real S3 leg — the one part of the pipeline that `FakeStorage` cannot cover.
 *
 * Skips when object storage is unreachable, so `pnpm test` works without Docker. It runs in CI, where
 * the MinIO image pulls normally, and locally after:
 *
 *   docker compose -f infra/docker/compose.dev.yml up -d minio
 *
 * This split is deliberate rather than convenient: the packaging tests prove the transcode, the
 * encryption, the manifests and the rows against an in-memory double, and this proves the bytes
 * actually reach storage under the keys the API will presign.
 */
const env: Env = {
  DATABASE_URL: process.env.DATABASE_URL ?? 'postgresql://unused',
  REDIS_URL: process.env.REDIS_URL ?? 'redis://localhost:6379',
  S3_ENDPOINT: process.env.S3_ENDPOINT ?? 'http://localhost:9000',
  S3_REGION: process.env.S3_REGION ?? 'us-east-1',
  S3_ACCESS_KEY: process.env.S3_ACCESS_KEY ?? 'tihe_minio',
  S3_SECRET_KEY: process.env.S3_SECRET_KEY ?? 'tihe_minio_dev_password',
  S3_FORCE_PATH_STYLE: true,
  S3_BUCKET_RAW: process.env.S3_BUCKET_RAW ?? 'tihe-raw',
  S3_BUCKET_VOD: process.env.S3_BUCKET_VOD ?? 'tihe-vod',
  KEK_BASE64: randomBytes(32).toString('base64'),
  RAW_RETENTION_DAYS: 7,
  MEDIA_WORK_DIR: '/tmp/tihe-media',
  MEDIA_CONCURRENCY: 1,
};

let reachable = false;
const storage = new Storage(env);
const prefix = `storage-test-${Date.now()}`;
const written: string[] = [];

beforeAll(async () => {
  try {
    // A HEAD on a key that does not exist still proves credentials and connectivity: it returns
    // cleanly rather than throwing a connection error.
    await storage.exists(storage.vodBucket, `${prefix}/probe`);
    await storage.putBuffer(
      storage.vodBucket,
      `${prefix}/probe`,
      Buffer.from('probe'),
      'text/plain',
    );
    written.push(`${prefix}/probe`);
    reachable = true;
  } catch {
    reachable = false;
  }
}, 30_000);

afterAll(async () => {
  if (!reachable) return;
  for (const key of written) {
    await storage.delete(storage.vodBucket, key).catch(() => undefined);
  }
});

describe.skipIf(!reachable)('Storage against real object storage', () => {
  it('round trips a manifest under the published key layout', async () => {
    const videoId = `vid_${prefix.replace(/[^a-zA-Z0-9]/g, '')}`;
    const key = vodKeys(videoId).master;
    const body = Buffer.from('#EXTM3U\n#EXT-X-VERSION:3\n');

    await storage.putBuffer(storage.vodBucket, key, body, CONTENT_TYPES.manifest);
    written.push(key);

    expect(await storage.exists(storage.vodBucket, key)).toBe(true);
  });

  it('round trips a binary segment without altering it', async () => {
    // A transport that mangles binary would corrupt every encrypted segment, and the symptom would
    // be indistinguishable from a decryption bug.
    const key = `${prefix}/segment.ts`;
    const body = randomBytes(4096);

    await storage.putBuffer(storage.vodBucket, key, body, CONTENT_TYPES.segment);
    written.push(key);

    expect(await storage.exists(storage.vodBucket, key)).toBe(true);
  });

  it('reports a missing object as absent rather than throwing', async () => {
    // Idempotency depends on this: a throw here would look like a storage outage and fail the job
    // instead of triggering a re-package.
    expect(await storage.exists(storage.vodBucket, `${prefix}/definitely-not-here`)).toBe(false);
  });

  it('deletes an object', async () => {
    const key = `${prefix}/to-delete`;
    await storage.putBuffer(storage.vodBucket, key, Buffer.from('x'), 'text/plain');

    await storage.delete(storage.vodBucket, key);

    expect(await storage.exists(storage.vodBucket, key)).toBe(false);
  });
});
