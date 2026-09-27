import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { createWriteStream } from 'node:fs';
import { pipeline } from 'node:stream/promises';
import type { Readable } from 'node:stream';

import type { Env } from './config.js';

/**
 * A storage failure, with enough context to act on.
 *
 * Distinguished from a transcode failure on purpose: one means "object storage is down or
 * misconfigured", the other means "this video is broken". Conflating them sends an operator looking
 * at the wrong thing.
 */
export class StorageError extends Error {
  constructor(
    message: string,
    readonly endpoint: string,
    override readonly cause: unknown,
  ) {
    const reason = cause instanceof Error ? cause.message : String(cause);
    const hint = /ECONNREFUSED|ENOTFOUND|EAI_AGAIN/.test(reason)
      ? ` — is object storage running? try: docker compose -f infra/docker/compose.dev.yml up -d minio`
      : '';
    super(`${message}: ${reason} [endpoint ${endpoint}]${hint}`);
    this.name = 'StorageError';
  }
}

/**
 * Object storage for the packager.
 *
 * The published layout is fixed by `StorageService.vodKeys` in the API — the API mints presigned URLs
 * against these exact paths, so the two must agree. Duplicated deliberately as a small pure function
 * rather than shared, because importing it would drag the whole NestJS graph into a worker; the
 * `vodKeys` test asserts the two stay identical.
 */
export function vodKeys(videoId: string) {
  return {
    master: `${videoId}/master.m3u8`,
    poster: `${videoId}/poster.jpg`,
    sprite: `${videoId}/sprite.jpg`,
    spriteVtt: `${videoId}/sprite.vtt`,
    renditionIndex: (label: string) => `${videoId}/${label}/index.m3u8`,
    segment: (label: string, seq: number) =>
      `${videoId}/${label}/seg-${String(seq).padStart(5, '0')}.ts`,
  };
}

export class Storage {
  private readonly client: S3Client;

  constructor(private readonly env: Env) {
    this.client = new S3Client({
      endpoint: env.S3_ENDPOINT,
      region: env.S3_REGION,
      credentials: {
        accessKeyId: env.S3_ACCESS_KEY,
        secretAccessKey: env.S3_SECRET_KEY,
      },
      forcePathStyle: env.S3_FORCE_PATH_STYLE,
    });
  }

  get vodBucket(): string {
    return this.env.S3_BUCKET_VOD;
  }

  get rawBucket(): string {
    return this.env.S3_BUCKET_RAW;
  }

  async putBuffer(bucket: string, key: string, body: Buffer, contentType: string): Promise<void> {
    try {
      await this.client.send(
        new PutObjectCommand({ Bucket: bucket, Key: key, Body: body, ContentType: contentType }),
      );
    } catch (error) {
      // A bare "connect ECONNREFUSED 127.0.0.1:9000" in a worker log says nothing about what was being
      // written or why. Naming the object and the likely cause is the difference between a two-minute
      // fix and an afternoon.
      throw new StorageError(
        `could not upload ${bucket}/${key} (${body.length} bytes)`,
        this.env.S3_ENDPOINT,
        error,
      );
    }
  }

  async exists(bucket: string, key: string): Promise<boolean> {
    try {
      await this.client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
      return true;
    } catch {
      return false;
    }
  }

  /** Pulls a source file down for transcoding. */
  async download(bucket: string, key: string, toPath: string): Promise<void> {
    const result = await this.client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    if (!result.Body) throw new Error(`${bucket}/${key} has no body`);
    await pipeline(result.Body as Readable, createWriteStream(toPath));
  }

  /**
   * Removes the unencrypted source after successful packaging.
   *
   * Not optional housekeeping: an unencrypted master left in object storage means the encryption
   * protects nothing against whoever holds a storage credential (docs/08-threat-model.md, T4).
   */
  async delete(bucket: string, key: string): Promise<void> {
    await this.client.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
  }
}

export const CONTENT_TYPES = {
  manifest: 'application/vnd.apple.mpegurl',
  segment: 'video/mp2t',
  jpeg: 'image/jpeg',
  vtt: 'text/vtt',
} as const;
