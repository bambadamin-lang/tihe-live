import { z } from 'zod';

const bool = z.enum(['true', 'false', '1', '0']).transform((v) => v === 'true' || v === '1');

/**
 * Environment for services/live, validated once at startup — a missing secret fails the boot,
 * not the first class. See services/live/.env.example.
 */
export const configSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().default(3100),

  LIVE_DATABASE_URL: z.string().url().optional(),
  /** Unset: rooms live in memory only and do not survive a restart (tests, quick dev). */
  REDIS_URL: z.string().url().optional(),

  /** Shared with services/api, which signs access tokens with it (ADR-0012). */
  JWT_SECRET: z.string().min(32),
  /** Signs the short-lived gateway tickets handed out at join. Not shared with anyone. */
  LIVE_TICKET_SECRET: z.string().min(32),

  /** What clients connect to. */
  LIVEKIT_URL: z.string(),
  /** What this service calls for the server API. Defaults to LIVEKIT_URL over http. */
  LIVEKIT_API_URL: z.string().optional(),
  LIVEKIT_API_KEY: z.string().min(1),
  LIVEKIT_API_SECRET: z.string().min(32),
  /** Development only: accept unsigned webhooks so they can be posted by hand. */
  LIVEKIT_WEBHOOK_ALLOW_UNSIGNED: bool.default('false'),

  /** The gateway URL clients receive in the join response. */
  PUBLIC_GATEWAY_URL: z.string().default('ws://localhost:3100/v1/live/ws'),
  /** The recording template and gateway as Egress's headless Chrome reaches them. */
  EGRESS_TEMPLATE_URL: z
    .string()
    .default('http://host.docker.internal:3100/v1/live/egress-template/index.html'),
  EGRESS_GATEWAY_URL: z.string().default('ws://host.docker.internal:3100/v1/live/ws'),

  S3_ENDPOINT: z.string().url().optional(),
  S3_REGION: z.string().default('us-east-1'),
  S3_ACCESS_KEY: z.string().optional(),
  S3_SECRET_KEY: z.string().optional(),
  S3_FORCE_PATH_STYLE: bool.default('true'),
  S3_BUCKET_RAW: z.string().default('tihe-raw'),

  /** `stub` reads services/live/dev/directory.json; `http` calls services/api internally. */
  DIRECTORY_MODE: z.enum(['stub', 'http']).default('stub'),
  DIRECTORY_STUB_FILE: z.string().default('dev/directory.json'),
  API_INTERNAL_URL: z.string().url().optional(),
  API_INTERNAL_TOKEN: z.string().optional(),

  /** Kill switch for the iOS secure-layer trick (ADR-0011). */
  IOS_SECURE_LAYER: bool.default('true'),
});
export type LiveConfig = z.infer<typeof configSchema>;

export const LIVE_CONFIG = Symbol('LIVE_CONFIG');

export function loadConfig(env: NodeJS.ProcessEnv = process.env): LiveConfig {
  const parsed = configSchema.safeParse(env);
  if (!parsed.success) {
    const problems = parsed.error.issues.map((i) => `  ${i.path.join('.')}: ${i.message}`);
    throw new Error(`services/live configuration is invalid:\n${problems.join('\n')}`);
  }
  const config = parsed.data;
  if (config.NODE_ENV === 'production') {
    if (config.LIVEKIT_WEBHOOK_ALLOW_UNSIGNED) {
      throw new Error('LIVEKIT_WEBHOOK_ALLOW_UNSIGNED must be false in production');
    }
    if (config.DIRECTORY_MODE !== 'http')
      throw new Error('DIRECTORY_MODE must be http in production');
    if (!config.REDIS_URL || !config.LIVE_DATABASE_URL) {
      throw new Error('REDIS_URL and LIVE_DATABASE_URL are required in production');
    }
  }
  return config;
}

export function livekitApiUrl(config: LiveConfig): string {
  return config.LIVEKIT_API_URL ?? config.LIVEKIT_URL.replace(/^ws/, 'http');
}
