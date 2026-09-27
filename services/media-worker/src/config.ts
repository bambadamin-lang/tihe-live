import { z } from 'zod';

/**
 * Worker configuration. Reads the same root `.env` as the API — notably the same `KEK_BASE64`,
 * because a packager wrapping content keys under a different KEK than the API unwraps with produces
 * a library of undecryptable video.
 */
export const envSchema = z.object({
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url().default('redis://localhost:6379'),

  S3_ENDPOINT: z.string().url(),
  S3_REGION: z.string().default('us-east-1'),
  S3_ACCESS_KEY: z.string().min(1),
  S3_SECRET_KEY: z.string().min(1),
  S3_FORCE_PATH_STYLE: z.coerce.boolean().default(true),
  S3_BUCKET_RAW: z.string().default('tihe-raw'),
  S3_BUCKET_VOD: z.string().default('tihe-vod'),

  KEK_BASE64: z
    .string()
    .min(1, 'KEK_BASE64 is required — run ./infra/scripts/generate-secrets.sh')
    .refine((v) => Buffer.from(v, 'base64').length === 32, {
      message: 'KEK_BASE64 must decode to exactly 32 bytes',
    }),

  RAW_RETENTION_DAYS: z.coerce.number().int().nonnegative().default(7),

  /** Where transcoding happens. Cleared after every job — plaintext video must not linger. */
  MEDIA_WORK_DIR: z.string().default('/tmp/tihe-media'),

  /** Concurrent ffmpeg jobs. One rendition saturates roughly one core, so keep this low. */
  MEDIA_CONCURRENCY: z.coerce.number().int().positive().max(8).default(1),
});

export type Env = z.infer<typeof envSchema>;

export function loadEnv(raw: NodeJS.ProcessEnv = process.env): Env {
  const parsed = envSchema.safeParse(raw);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `  ${i.path.join('.')}: ${i.message}`).join('\n');
    throw new Error(`Invalid media-worker configuration:\n${issues}`);
  }
  return parsed.data;
}
