import { spawnSync } from 'node:child_process';
import { mkdtemp, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createDecipheriv, randomBytes } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { segmentIv, unwrapContentKeyWithKek } from '@tihe/crypto';
import { newId, PrismaClient } from '@tihe/db';

import type { Env } from '../src/config.js';
import { Packager } from '../src/packager.js';
import { vodKeys } from '../src/storage.js';
import { FakeStorage } from './fake-storage.js';

/**
 * End-to-end packaging, with a real ffmpeg transcode.
 *
 * Needs ffmpeg and a database. Skips rather than fails without them, so `pnpm test` works on a
 * machine that has neither — CI provides both.
 */
const hasFfmpeg = spawnSync('ffmpeg', ['-version']).status === 0;
const hasDatabase = Boolean(process.env.DATABASE_URL);
const canRun = hasFfmpeg && hasDatabase;

const KEK = randomBytes(32).toString('base64');

describe.skipIf(!canRun)('Packager', () => {
  let prisma: PrismaClient;
  let workDir: string;
  let sourceDir: string;
  let courseId: string;

  const env = (): Env =>
    ({
      DATABASE_URL: process.env.DATABASE_URL!,
      REDIS_URL: 'redis://localhost:6379',
      S3_ENDPOINT: 'http://localhost:9000',
      S3_REGION: 'us-east-1',
      S3_ACCESS_KEY: 'x',
      S3_SECRET_KEY: 'y',
      S3_FORCE_PATH_STYLE: true,
      S3_BUCKET_RAW: 'tihe-raw',
      S3_BUCKET_VOD: 'tihe-vod',
      KEK_BASE64: KEK,
      RAW_RETENTION_DAYS: 7,
      MEDIA_WORK_DIR: workDir,
      MEDIA_CONCURRENCY: 1,
    }) satisfies Env;

  /** A short synthetic lecture: colour bars plus a tone, at a size that exercises the ladder. */
  function makeSource(name: string, size: string, seconds: number, withAudio = true): string {
    const path = join(sourceDir, name);
    const args = [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-f',
      'lavfi',
      '-i',
      `testsrc=size=${size}:rate=25:duration=${seconds}`,
      ...(withAudio ? ['-f', 'lavfi', '-i', `sine=frequency=440:duration=${seconds}`] : []),
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-pix_fmt',
      'yuv420p',
      ...(withAudio ? ['-c:a', 'aac', '-shortest'] : []),
      path,
    ];
    const result = spawnSync('ffmpeg', args);
    if (result.status !== 0) {
      throw new Error(`could not build fixture video: ${result.stderr?.toString().slice(-400)}`);
    }
    return path;
  }

  async function createVideo(title: string): Promise<string> {
    const video = await prisma.video.create({
      data: { id: newId('video'), courseId, title, source: 'upload', status: 'processing' },
    });
    return video.id;
  }

  beforeAll(async () => {
    prisma = new PrismaClient();
    workDir = await mkdtemp(join(tmpdir(), 'pkg-work-'));
    sourceDir = await mkdtemp(join(tmpdir(), 'pkg-src-'));

    const term = await prisma.term.create({
      data: {
        id: newId('term'),
        title: 'packager test term',
        startsAt: new Date(),
        endsAt: new Date(Date.now() + 86_400_000),
      },
    });
    const course = await prisma.course.create({
      data: {
        id: newId('course'),
        termId: term.id,
        title: 'packager test course',
        slug: `packager-test-${Date.now()}`,
        status: 'published',
      },
    });
    courseId = course.id;
  }, 120_000);

  afterAll(async () => {
    // Cascades to videos, assets and content keys.
    await prisma.course.deleteMany({ where: { id: courseId } }).catch(() => undefined);
    await prisma.$disconnect();
    await rm(workDir, { recursive: true, force: true });
    await rm(sourceDir, { recursive: true, force: true });
  });

  it('packages a 480p source into one video rendition plus audio', async () => {
    const source = makeSource('480p.mp4', '640x480', 13);
    const videoId = await createVideo('packaged 480p');
    const storage = new FakeStorage();

    const result = await new Packager(prisma, storage.asStorage(), env()).package({
      videoId,
      sourcePath: source,
    });

    expect(result.skipped).toBe(false);
    expect(result.renditions.map((r) => r.label)).toEqual(['480p', 'audio']);
    // 13 seconds at 6-second segments.
    expect(result.renditions[0]!.segmentCount).toBeGreaterThanOrEqual(2);
    expect(result.durationMs).toBeGreaterThan(12_000);

    const keys = vodKeys(videoId);
    expect(storage.text(storage.vodBucket, keys.master)).toContain('480p/index.m3u8');
    expect(storage.get(storage.vodBucket, keys.segment('480p', 0))).toBeDefined();
    expect(storage.get(storage.vodBucket, keys.poster)).toBeDefined();
    expect(storage.text(storage.vodBucket, keys.spriteVtt)).toContain('WEBVTT');
  });

  it('publishes no manifest containing a key line', async () => {
    // The rule the whole design rests on: the key never travels with the media.
    const source = makeSource('nokey.mp4', '640x480', 7);
    const videoId = await createVideo('no key line');
    const storage = new FakeStorage();

    await new Packager(prisma, storage.asStorage(), env()).package({ videoId, sourcePath: source });

    for (const key of storage.keysUnder('.m3u8')) {
      expect(storage.objects.get(key)!.body.toString('utf8')).not.toContain('EXT-X-KEY');
    }
  });

  it('writes asset rows that agree with what was uploaded', async () => {
    const source = makeSource('rows.mp4', '640x480', 13);
    const videoId = await createVideo('rows agree');
    const storage = new FakeStorage();

    await new Packager(prisma, storage.asStorage(), env()).package({ videoId, sourcePath: source });

    const video = await prisma.video.findUniqueOrThrow({
      where: { id: videoId },
      include: { assets: true, contentKeys: true },
    });

    expect(video.status).toBe('ready');
    expect(video.durationMs).toBeGreaterThan(0);
    expect(video.publishedAt).not.toBeNull();
    expect(video.contentKeys).toHaveLength(1);

    const keys = vodKeys(videoId);
    for (const asset of video.assets) {
      // Every segment the row claims must actually exist, or a student hits a 404 mid-lecture.
      for (let seq = 0; seq < asset.segmentCount; seq += 1) {
        expect(
          storage.get(storage.vodBucket, keys.segment(asset.label, seq)),
          `${asset.label} segment ${seq} missing`,
        ).toBeDefined();
      }
      expect(asset.targetDuration).toBe(6);
      expect(Number(asset.byteSize)).toBeGreaterThan(0);
      expect(asset.storageKey).toBe(keys.renditionIndex(asset.label));
    }
  });

  it('encrypts segments so that the stored bytes are not playable video', async () => {
    const source = makeSource('encrypted.mp4', '640x480', 7);
    const videoId = await createVideo('encrypted');
    const storage = new FakeStorage();

    const result = await new Packager(prisma, storage.asStorage(), env()).package({
      videoId,
      sourcePath: source,
    });

    const stored = storage.get(storage.vodBucket, vodKeys(videoId).segment('480p', 0))!;

    // An MPEG-TS packet starts with 0x47 every 188 bytes. Encrypted bytes will not, which is exactly
    // what makes this a cheap and sharp check.
    const syncBytesIntact = [0, 188, 376, 564].every((offset) => stored[offset] === 0x47);
    expect(syncBytesIntact).toBe(false);

    // And it decrypts back to real TS with the key the API would unwrap.
    const contentKeyRow = await prisma.contentKey.findFirstOrThrow({ where: { videoId } });
    const cek = unwrapContentKeyWithKek(contentKeyRow.wrappedKey, KEK);
    const decipher = createDecipheriv('aes-128-ctr', cek, segmentIv(result.contentKeyId, 0));
    const plain = Buffer.concat([decipher.update(stored), decipher.final()]);

    for (const offset of [0, 188, 376, 564]) {
      expect(plain[offset], `TS sync byte missing at ${offset} after decryption`).toBe(0x47);
    }
  });

  it('is idempotent: a second run neither re-encodes nor mints a second key', async () => {
    // BullMQ retries a crashed job. A retry that duplicated output would double the storage bill and
    // a second content key would orphan every already-published segment.
    const source = makeSource('idem.mp4', '640x480', 7);
    const videoId = await createVideo('idempotent');
    const storage = new FakeStorage();
    const packager = new Packager(prisma, storage.asStorage(), env());

    const first = await packager.package({ videoId, sourcePath: source });
    const objectCount = storage.objects.size;

    const second = await packager.package({ videoId, sourcePath: source });

    expect(second.skipped).toBe(true);
    expect(second.contentKeyId).toBe(first.contentKeyId);
    expect(storage.objects.size).toBe(objectCount);
    expect(await prisma.contentKey.count({ where: { videoId } })).toBe(1);
    expect(await prisma.videoAsset.count({ where: { videoId } })).toBe(first.renditions.length);
  });

  it('re-packages when the objects have gone missing', async () => {
    // Rows written but the upload died. The video is `ready` and unplayable, so the retry must redo
    // the work rather than trust the rows.
    const source = makeSource('missing.mp4', '640x480', 7);
    const videoId = await createVideo('objects missing');
    const storage = new FakeStorage();
    const packager = new Packager(prisma, storage.asStorage(), env());

    await packager.package({ videoId, sourcePath: source });
    storage.objects.delete(`${storage.vodBucket}/${vodKeys(videoId).master}`);

    const again = await packager.package({ videoId, sourcePath: source });

    expect(again.skipped).toBe(false);
    expect(storage.get(storage.vodBucket, vodKeys(videoId).master)).toBeDefined();
  });

  it('leaves no plaintext behind, on success or on failure', async () => {
    // The work directory holds decrypted video. Anything left there after a job defeats the point of
    // encrypting the output at all.
    const source = makeSource('cleanup.mp4', '640x480', 7);
    const videoId = await createVideo('cleanup');
    const storage = new FakeStorage();

    await new Packager(prisma, storage.asStorage(), env()).package({ videoId, sourcePath: source });

    const leftovers = (await import('node:fs/promises')).readdir(workDir);
    expect((await leftovers).filter((f) => f.startsWith('pkg-'))).toEqual([]);
  });

  it('marks a video failed and cleans up when the source is unusable', async () => {
    const videoId = await createVideo('bad source');
    const storage = new FakeStorage();
    const bogus = join(sourceDir, 'not-a-video.mp4');
    await (await import('node:fs/promises')).writeFile(bogus, 'this is not a video file');

    await expect(
      new Packager(prisma, storage.asStorage(), env()).package({ videoId, sourcePath: bogus }),
    ).rejects.toThrow();

    const video = await prisma.video.findUniqueOrThrow({ where: { id: videoId } });
    expect(video.status).toBe('failed');

    const entries = await (await import('node:fs/promises')).readdir(workDir);
    expect(entries.filter((f) => f.startsWith('pkg-'))).toEqual([]);
  });

  it('produces audio only for a source with no video track', async () => {
    const path = join(sourceDir, 'audio-only.m4a');
    spawnSync('ffmpeg', [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:duration=7',
      '-c:a',
      'aac',
      path,
    ]);
    await stat(path);

    const videoId = await createVideo('audio only');
    const storage = new FakeStorage();

    const result = await new Packager(prisma, storage.asStorage(), env()).package({
      videoId,
      sourcePath: path,
    });

    expect(result.renditions.map((r) => r.label)).toEqual(['audio']);
    // No poster for something with no picture, rather than a black frame.
    expect(storage.get(storage.vodBucket, vodKeys(videoId).poster)).toBeUndefined();
  });
});
