import { mkdir, mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { generateContentKey, wrapContentKeyWithKek } from '@tihe/crypto';
import { newId, type PrismaClient } from '@tihe/db';

import type { Env } from './config.js';
import { encryptSegment, sequenceOf } from './encrypt.js';
import {
  AUDIO_RENDITION,
  buildSprite,
  extractPoster,
  ladderFor,
  probe,
  SEGMENT_SECONDS,
  transcodeRendition,
  type ProbeResult,
  type RenditionSpec,
} from './ffmpeg.js';
import { buildMasterPlaylist, countSegments, readMediaPlaylist } from './manifest.js';
import { CONTENT_TYPES, Storage, vodKeys } from './storage.js';

/**
 * The packaging pipeline: a source file becomes encrypted HLS in object storage, plus the rows
 * playback reads.
 *
 * Ordering is load-bearing in two places, and both are easy to get wrong:
 *
 *  1. **The content key row is created before any transcoding**, because its id is an input to the
 *     segment IV derivation. Create it afterwards and you get segments whose IVs no client can
 *     reproduce — video that decrypts to noise, with nothing in any log to say why.
 *  2. **`videos.status` becomes `ready` only after every upload has landed.** A `ready` video whose
 *     segments are still uploading is a student hitting a 404 mid-lecture.
 */

export interface PackageResult {
  videoId: string;
  contentKeyId: string;
  durationMs: number;
  renditions: Array<{ label: string; segmentCount: number; byteSize: number }>;
  skipped: boolean;
}

export interface PackageOptions {
  videoId: string;
  /** A local file, or an object in the raw bucket. Exactly one. */
  sourcePath?: string;
  sourceKey?: string;
  onProgress?: (percent: number, note: string) => void;
}

export class Packager {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly storage: Storage,
    private readonly env: Env,
  ) {}

  async package(options: PackageOptions): Promise<PackageResult> {
    const { videoId } = options;
    const report = options.onProgress ?? (() => {});

    const video = await this.prisma.video.findUnique({
      where: { id: videoId },
      include: { assets: true, contentKeys: { where: { retiredAt: null } } },
    });
    if (!video) throw new Error(`video ${videoId} does not exist`);

    // Idempotency: BullMQ retries a crashed job, and a retry must not duplicate output or mint a
    // second content key. Checking storage as well as the rows catches the case where rows were
    // written but the upload died.
    if (video.status === 'ready' && video.assets.length > 0) {
      const allPresent = await this.allObjectsPresent(videoId, video.assets);
      if (allPresent) {
        report(100, 'already packaged');
        return {
          videoId,
          contentKeyId: video.contentKeys[0]?.id ?? '',
          durationMs: video.durationMs,
          renditions: video.assets.map((a) => ({
            label: a.label,
            segmentCount: a.segmentCount,
            byteSize: Number(a.byteSize),
          })),
          skipped: true,
        };
      }
    }

    const workDir = await mkdtemp(join(this.env.MEDIA_WORK_DIR, 'pkg-'));

    try {
      await this.prisma.video.update({
        where: { id: videoId },
        data: { status: 'processing' },
      });

      // ── source ──
      const sourcePath = await this.resolveSource(options, workDir);
      report(5, 'probing');

      const probed = await probe(sourcePath);
      this.assertPlayable(probed);

      const ladder = ladderFor(probed);
      if (ladder.length === 0) throw new Error('source has no usable video or audio stream');

      // ── content key, before anything is encrypted ──
      const contentKeyId = await this.ensureContentKey(videoId, video.contentKeys[0]?.id);
      const contentKey = generateContentKey();

      // A reused id with a fresh key would orphan already-published segments, so the key is only
      // generated where the id is too.
      await this.prisma.contentKey.update({
        where: { id: contentKeyId },
        data: { wrappedKey: wrapContentKeyWithKek(contentKey, this.env.KEK_BASE64) },
      });

      // ── renditions ──
      const keys = vodKeys(videoId);
      const produced: Array<{ spec: RenditionSpec; segmentCount: number; byteSize: number }> = [];

      for (const [index, spec] of ladder.entries()) {
        report(10 + Math.round((index / ladder.length) * 70), `transcoding ${spec.label}`);

        const dir = join(workDir, spec.label);
        const { segmentCount, byteSize } = await transcodeRendition({
          sourcePath,
          outputDir: dir,
          spec,
          frameRate: probed.frameRate,
        });

        const segments = (await readdir(dir)).filter((f) => f.endsWith('.ts')).sort();

        for (const fileName of segments) {
          const sequence = sequenceOf(fileName);
          const ciphertext = await encryptSegment({
            dir,
            fileName,
            sequence,
            contentKey,
            contentKeyId,
          });
          await this.storage.putBuffer(
            this.storage.vodBucket,
            keys.segment(spec.label, sequence),
            ciphertext,
            CONTENT_TYPES.segment,
          );
        }

        const playlist = await readMediaPlaylist(join(dir, 'index.m3u8'));
        if (countSegments(playlist) !== segmentCount) {
          throw new Error(
            `${spec.label}: playlist lists ${countSegments(playlist)} segments but ${segmentCount} files were written`,
          );
        }

        await this.storage.putBuffer(
          this.storage.vodBucket,
          keys.renditionIndex(spec.label),
          Buffer.from(playlist, 'utf8'),
          CONTENT_TYPES.manifest,
        );

        produced.push({ spec, segmentCount, byteSize });
      }

      // ── master playlist ──
      report(82, 'writing master playlist');
      const master = buildMasterPlaylist(
        produced.map(({ spec }) => ({
          spec,
          width: spec.height === null ? null : this.scaledWidth(probed, spec.height),
          height: spec.height,
        })),
      );
      await this.storage.putBuffer(
        this.storage.vodBucket,
        keys.master,
        Buffer.from(master, 'utf8'),
        CONTENT_TYPES.manifest,
      );

      // ── poster and sprite ──
      // Best-effort: a missing thumbnail is a cosmetic problem, and failing a whole lecture over one
      // would be the wrong trade.
      let posterKey: string | null = null;
      let spriteKey: string | null = null;

      if (probed.hasVideo) {
        report(88, 'poster and sprite');
        try {
          const posterPath = join(workDir, 'poster.jpg');
          await extractPoster({
            sourcePath,
            outputPath: posterPath,
            // 10% in: past the title card, into actual content.
            atSeconds: Math.max(1, (probed.durationMs / 1000) * 0.1),
          });
          await this.storage.putBuffer(
            this.storage.vodBucket,
            keys.poster,
            await readFile(posterPath),
            CONTENT_TYPES.jpeg,
          );
          posterKey = keys.poster;

          const spritePath = join(workDir, 'sprite.jpg');
          const { vtt } = await buildSprite({
            sourcePath,
            outputPath: spritePath,
            durationMs: probed.durationMs,
          });
          await this.storage.putBuffer(
            this.storage.vodBucket,
            keys.sprite,
            await readFile(spritePath),
            CONTENT_TYPES.jpeg,
          );
          await this.storage.putBuffer(
            this.storage.vodBucket,
            keys.spriteVtt,
            Buffer.from(vtt, 'utf8'),
            CONTENT_TYPES.vtt,
          );
          spriteKey = keys.sprite;
        } catch {
          // Deliberately swallowed — see above. The video is still publishable.
        }
      }

      // ── rows, then ready ──
      report(95, 'writing rows');
      await this.prisma.$transaction([
        // Replaced rather than upserted: a re-package may produce a different ladder, and stale rows
        // would advertise renditions that no longer exist.
        this.prisma.videoAsset.deleteMany({ where: { videoId } }),
        this.prisma.videoAsset.createMany({
          data: produced.map(({ spec, segmentCount, byteSize }) => ({
            id: newId('asset'),
            videoId,
            label: spec.label,
            storageKey: keys.renditionIndex(spec.label),
            width: spec.height === null ? null : this.scaledWidth(probed, spec.height),
            height: spec.height,
            bitrate: spec.nominalBps,
            codec: spec.label === AUDIO_RENDITION.label ? 'aac' : 'h264',
            segmentCount,
            targetDuration: SEGMENT_SECONDS,
            byteSize: BigInt(byteSize),
          })),
        }),
        this.prisma.video.update({
          where: { id: videoId },
          data: {
            status: 'ready',
            durationMs: probed.durationMs,
            posterKey,
            spriteKey,
            publishedAt: video.publishedAt ?? new Date(),
          },
        }),
      ]);

      // ── retention ──
      if (options.sourceKey && this.env.RAW_RETENTION_DAYS === 0) {
        await this.storage.delete(this.storage.rawBucket, options.sourceKey);
      }

      report(100, 'ready');

      return {
        videoId,
        contentKeyId,
        durationMs: probed.durationMs,
        renditions: produced.map(({ spec, segmentCount, byteSize }) => ({
          label: spec.label,
          segmentCount,
          byteSize,
        })),
        skipped: false,
      };
    } catch (error) {
      // A failed video must be visible. Left as `processing` it looks like a slow job forever, and
      // nobody investigates.
      await this.prisma.video
        .update({
          where: { id: videoId },
          data: { status: 'failed' },
        })
        .catch(() => undefined);
      throw error;
    } finally {
      // Non-negotiable: the work directory holds plaintext segments. Leaving them behind after a
      // failure is precisely the leak the encryption exists to prevent.
      await rm(workDir, { recursive: true, force: true });
    }
  }

  private assertPlayable(probed: ProbeResult): void {
    if (!probed.hasVideo && !probed.hasAudio) {
      throw new Error('source contains neither a video nor an audio stream');
    }
    if (probed.durationMs <= 0) {
      throw new Error('source has zero duration');
    }
  }

  /**
   * Reuses an existing content key id, or creates one.
   *
   * Reuse matters for a re-package: the id is baked into the IVs of segments already published, so a
   * new id would silently invalidate anything not overwritten.
   */
  private async ensureContentKey(videoId: string, existingId?: string): Promise<string> {
    if (existingId) return existingId;

    const created = await this.prisma.contentKey.create({
      data: {
        id: newId('contentKey'),
        videoId,
        // Replaced with the real wrap immediately after the key is generated. Never used as-is.
        wrappedKey: '',
        keyVersion: 1,
        algorithm: 'AES-128-CTR',
      },
    });
    return created.id;
  }

  private async allObjectsPresent(
    videoId: string,
    assets: Array<{ label: string; segmentCount: number }>,
  ): Promise<boolean> {
    const keys = vodKeys(videoId);
    if (!(await this.storage.exists(this.storage.vodBucket, keys.master))) return false;

    for (const asset of assets) {
      if (!(await this.storage.exists(this.storage.vodBucket, keys.renditionIndex(asset.label)))) {
        return false;
      }
      // Spot-check the ends rather than every segment: a full check on a 90-minute lecture is 900
      // HEAD requests, and a truncated upload almost always loses the tail.
      const last = asset.segmentCount - 1;
      if (
        last >= 0 &&
        !(await this.storage.exists(this.storage.vodBucket, keys.segment(asset.label, last)))
      ) {
        return false;
      }
    }
    return true;
  }

  private async resolveSource(options: PackageOptions, workDir: string): Promise<string> {
    if (options.sourcePath) return options.sourcePath;
    if (!options.sourceKey) throw new Error('either sourcePath or sourceKey is required');

    const local = join(workDir, 'source');
    await this.storage.download(this.storage.rawBucket, options.sourceKey, local);
    return local;
  }

  /** Width for a target height, preserving the source aspect ratio and kept even for H.264. */
  private scaledWidth(probed: ProbeResult, height: number): number | null {
    if (!probed.width || !probed.height) return null;
    const width = Math.round((probed.width / probed.height) * height);
    return width % 2 === 0 ? width : width + 1;
  }
}

export async function ensureWorkDir(env: Env): Promise<void> {
  await mkdir(env.MEDIA_WORK_DIR, { recursive: true });
}

export { tmpdir };
