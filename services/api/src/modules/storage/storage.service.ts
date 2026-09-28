import { GetObjectCommand, HeadObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import type { Env } from '../../config/configuration.js';

/**
 * Object storage access.
 *
 * Two rules, both from docs/03-content-protection.md:
 *
 * 1. **Media bytes never pass through the API.** Clients fetch segments straight from storage via
 *    presigned URLs, so the API stays small and cheap and does not become a bandwidth bottleneck.
 * 2. **Presigns are short-lived** (2 minutes by default) and minted only after enrollment and
 *    licence checks pass. A leaked URL is worthless within minutes.
 *
 * Nothing here names MinIO. Any S3-compatible provider works by changing environment variables —
 * see docs/adr/0004.
 */
@Injectable()
export class StorageService {
  private readonly logger = new Logger(StorageService.name);
  private readonly client: S3Client;
  private readonly publicClient: S3Client;

  constructor(private readonly config: ConfigService<Env, true>) {
    const credentials = {
      accessKeyId: this.config.getOrThrow('S3_ACCESS_KEY', { infer: true }),
      secretAccessKey: this.config.getOrThrow('S3_SECRET_KEY', { infer: true }),
    };
    const region = this.config.getOrThrow('S3_REGION', { infer: true });
    const forcePathStyle = this.config.getOrThrow('S3_FORCE_PATH_STYLE', { infer: true });

    this.client = new S3Client({
      endpoint: this.config.getOrThrow('S3_ENDPOINT', { infer: true }),
      region,
      credentials,
      forcePathStyle,
    });

    // Presigned URLs are only valid for the hostname they were signed against. When clients reach
    // storage through a reverse proxy, that is not the internal endpoint the API uses — signing
    // with the wrong one produces URLs that fail for every client while working in local testing.
    const publicEndpoint =
      this.config.get('S3_PUBLIC_ENDPOINT', { infer: true }) ??
      this.config.getOrThrow('S3_ENDPOINT', { infer: true });

    this.publicClient = new S3Client({
      endpoint: publicEndpoint,
      region,
      credentials,
      forcePathStyle,
    });
  }

  get vodBucket(): string {
    return this.config.getOrThrow('S3_BUCKET_VOD', { infer: true });
  }

  get rawBucket(): string {
    return this.config.getOrThrow('S3_BUCKET_RAW', { infer: true });
  }

  /** A presigned GET for a client, signed for the public hostname. */
  async presignGet(bucket: string, key: string, ttlSeconds?: number): Promise<string> {
    const expiresIn =
      ttlSeconds ?? this.config.getOrThrow('S3_PRESIGN_TTL_SECONDS', { infer: true });
    return getSignedUrl(this.publicClient, new GetObjectCommand({ Bucket: bucket, Key: key }), {
      expiresIn,
    });
  }

  /** Whether an object exists — used to distinguish "still processing" from "lost". */
  async exists(bucket: string, key: string): Promise<boolean> {
    try {
      await this.client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
      return true;
    } catch {
      return false;
    }
  }

  async readJson<T>(bucket: string, key: string): Promise<T | null> {
    try {
      const result = await this.client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
      const body = await result.Body?.transformToString();
      return body ? (JSON.parse(body) as T) : null;
    } catch (error) {
      this.logger.warn(`could not read ${bucket}/${key}: ${(error as Error).message}`);
      return null;
    }
  }

  /** The storage layout written by media-worker. Kept in one place so it cannot drift. */
  static vodKeys(videoId: string) {
    const base = `${videoId}`;
    return {
      master: `${base}/master.m3u8`,
      poster: `${base}/poster.jpg`,
      sprite: `${base}/sprite.jpg`,
      spriteVtt: `${base}/sprite.vtt`,
      renditionIndex: (label: string) => `${base}/${label}/index.m3u8`,
      segment: (label: string, seq: number) =>
        `${base}/${label}/seg-${String(seq).padStart(5, '0')}.ts`,
    };
  }
}
