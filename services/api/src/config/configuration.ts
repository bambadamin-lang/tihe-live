import { z } from 'zod';

/**
 * Environment schema. Validated at boot, so a missing KEK fails immediately and loudly rather
 * than at the first playback request.
 *
 * The cryptographic values have no defaults on purpose: a development fallback for the KEK would
 * eventually reach production, and every video encrypted under it would be readable by anyone
 * who has read this repository.
 */
const base64of = (bytes: number, label: string) =>
  z
    .string()
    .min(1, `${label} is required — run ./infra/scripts/generate-secrets.sh`)
    .refine((v) => Buffer.from(v, 'base64').length >= bytes, {
      message: `${label} must decode to at least ${bytes} bytes`,
    });

export const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  API_PREFIX: z.string().default('v1'),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),

  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url().default('redis://localhost:6379'),

  S3_ENDPOINT: z.string().url(),
  S3_PUBLIC_ENDPOINT: z.string().url().optional(),
  S3_REGION: z.string().default('us-east-1'),
  S3_ACCESS_KEY: z.string().min(1),
  S3_SECRET_KEY: z.string().min(1),
  S3_FORCE_PATH_STYLE: z.coerce.boolean().default(true),
  S3_BUCKET_RAW: z.string().default('tihe-raw'),
  S3_BUCKET_VOD: z.string().default('tihe-vod'),
  S3_PRESIGN_TTL_SECONDS: z.coerce.number().int().positive().max(3600).default(120),

  KEK_BASE64: base64of(32, 'KEK_BASE64'),
  LICENSE_PRIVATE_KEY_BASE64: z.string().min(1, 'LICENSE_PRIVATE_KEY_BASE64 is required'),
  LICENSE_PUBLIC_KEY_BASE64: z.string().min(1, 'LICENSE_PUBLIC_KEY_BASE64 is required'),
  JWT_SECRET: base64of(32, 'JWT_SECRET'),
  OTP_PEPPER: base64of(16, 'OTP_PEPPER'),

  ACCESS_TOKEN_TTL: z.string().default('15m'),
  REFRESH_TOKEN_TTL: z.string().default('30d'),

  SMS_PROVIDER: z.enum(['console', 'kavenegar']).default('console'),
  SMS_API_KEY: z.string().optional(),
  SMS_SENDER: z.string().optional(),
  OTP_LENGTH: z.coerce.number().int().min(4).max(8).default(5),
  OTP_TTL_SECONDS: z.coerce.number().int().positive().default(120),
  OTP_RESEND_AFTER_SECONDS: z.coerce.number().int().positive().default(60),
  OTP_MAX_PER_PHONE_PER_HOUR: z.coerce.number().int().positive().default(5),
  OTP_MAX_PER_IP_PER_HOUR: z.coerce.number().int().positive().default(20),
  OTP_MAX_ATTEMPTS: z.coerce.number().int().positive().default(5),

  DEFAULT_MAX_DEVICES: z.coerce.number().int().positive().default(2),
  DEFAULT_MAX_CONCURRENT_STREAMS: z.coerce.number().int().positive().default(1),
  DEFAULT_OFFLINE_WINDOW_DAYS: z.coerce.number().int().positive().default(30),
  PLAYBACK_SESSION_TTL_SECONDS: z.coerce.number().int().positive().default(7200),
  PLAYBACK_HEARTBEAT_SECONDS: z.coerce.number().int().positive().default(30),

  LIVEKIT_API_KEY: z.string().default('devkey'),
  LIVEKIT_API_SECRET: z.string().default(''),
  LIVEKIT_WEBHOOK_ALLOW_UNSIGNED: z.coerce.boolean().default(false),

  RAW_RETENTION_DAYS: z.coerce.number().int().nonnegative().default(7),
});

export type Env = z.infer<typeof envSchema>;

export function validateEnv(raw: Record<string, unknown>): Env {
  const parsed = envSchema.safeParse(raw);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `  ${i.path.join('.')}: ${i.message}`).join('\n');
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }

  // A production deployment that accepts unsigned webhooks would let anyone inject a fake
  // recording into the library. Refuse to start rather than log a warning nobody reads.
  if (parsed.data.NODE_ENV === 'production' && parsed.data.LIVEKIT_WEBHOOK_ALLOW_UNSIGNED) {
    throw new Error('LIVEKIT_WEBHOOK_ALLOW_UNSIGNED must be false in production');
  }
  if (parsed.data.NODE_ENV === 'production' && !parsed.data.LIVEKIT_API_SECRET) {
    throw new Error('LIVEKIT_API_SECRET is required in production');
  }

  return parsed.data;
}
