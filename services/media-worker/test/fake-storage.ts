import type { Storage } from '../src/storage.js';

/**
 * An in-memory stand-in for object storage.
 *
 * MinIO cannot be reached from the build container this was developed in (the image is refused on
 * Docker Hub and quay.io, and dl.min.io returns 403), so the packaging pipeline is verified against
 * this instead. That covers everything except the S3 wire protocol itself: the transcode, the
 * encryption, the manifests, the object layout and the database rows are all exercised for real.
 *
 * The S3 leg is covered separately by `storage.integration.test.ts`, which runs against a real MinIO
 * in CI and locally.
 */
export class FakeStorage {
  readonly objects = new Map<string, { body: Buffer; contentType: string }>();
  readonly deleted: string[] = [];

  constructor(
    readonly vodBucket = 'tihe-vod',
    readonly rawBucket = 'tihe-raw',
  ) {}

  async putBuffer(bucket: string, key: string, body: Buffer, contentType: string): Promise<void> {
    this.objects.set(`${bucket}/${key}`, { body, contentType });
  }

  async exists(bucket: string, key: string): Promise<boolean> {
    return this.objects.has(`${bucket}/${key}`);
  }

  async download(): Promise<void> {
    throw new Error('FakeStorage.download is not used by these tests');
  }

  async delete(bucket: string, key: string): Promise<void> {
    this.objects.delete(`${bucket}/${key}`);
    this.deleted.push(`${bucket}/${key}`);
  }

  /** Test helpers. */
  get(bucket: string, key: string): Buffer | undefined {
    return this.objects.get(`${bucket}/${key}`)?.body;
  }

  text(bucket: string, key: string): string | undefined {
    return this.get(bucket, key)?.toString('utf8');
  }

  keysUnder(prefix: string): string[] {
    return [...this.objects.keys()].filter((k) => k.includes(prefix)).sort();
  }

  asStorage(): Storage {
    return this as unknown as Storage;
  }
}
