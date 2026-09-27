import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';

/** Where services/live writes `metadata.json` next to each recording (docs/06, Part 1). */
export interface ObjectStore {
  putJson(key: string, value: unknown): Promise<void>;
}
export const OBJECT_STORE = Symbol('OBJECT_STORE');

export class S3ObjectStore implements ObjectStore {
  private readonly s3: S3Client;

  constructor(
    opts: {
      endpoint: string;
      region: string;
      accessKey: string;
      secretKey: string;
      forcePathStyle: boolean;
    },
    private readonly bucket: string,
  ) {
    this.s3 = new S3Client({
      endpoint: opts.endpoint,
      region: opts.region,
      forcePathStyle: opts.forcePathStyle,
      credentials: { accessKeyId: opts.accessKey, secretAccessKey: opts.secretKey },
    });
  }

  async putJson(key: string, value: unknown): Promise<void> {
    await this.s3.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: JSON.stringify(value, null, 2),
        ContentType: 'application/json; charset=utf-8',
      }),
    );
  }
}

/** For tests and for running without MinIO: keeps objects in memory, in write order. */
export class MemoryObjectStore implements ObjectStore {
  readonly objects = new Map<string, unknown>();
  readonly writes: string[] = [];

  async putJson(key: string, value: unknown): Promise<void> {
    this.objects.set(key, structuredClone(value));
    this.writes.push(key);
  }
}
