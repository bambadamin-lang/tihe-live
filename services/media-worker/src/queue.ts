import { Queue, Worker, type Job } from 'bullmq';
import IORedis from 'ioredis';

import type { Env } from './config.js';

/**
 * BullMQ wiring.
 *
 * The queue name and job name are the contract with the API's LiveKit webhook (M2b) — it enqueues
 * `media:package` onto `media`, and this worker consumes it. Specified in
 * docs/06-recording-pipeline.md.
 */

export const MEDIA_QUEUE = 'media';
export const PACKAGE_JOB = 'media:package';

export interface PackageJobData {
  videoId: string;
  /** An object in the raw bucket. Omitted when the source is already local. */
  sourceKey?: string;
}

/** BullMQ requires maxRetriesPerRequest to be null for a blocking connection. */
export function createRedis(env: Env): IORedis {
  return new IORedis(env.REDIS_URL, { maxRetriesPerRequest: null });
}

export function createQueue(connection: IORedis): Queue<PackageJobData> {
  return new Queue<PackageJobData>(MEDIA_QUEUE, {
    connection,
    defaultJobOptions: {
      // Three attempts with a long backoff: a transcode failure is rarely transient, but a storage
      // blip is, and re-running a 90-minute transcode immediately would just burn the CPU twice.
      attempts: 3,
      backoff: { type: 'exponential', delay: 30_000 },
      removeOnComplete: { age: 86_400, count: 500 },
      // Failures are kept far longer than successes: a failed lecture is something a human has to
      // look at, and the job is the only record of why.
      removeOnFail: { age: 30 * 86_400 },
    },
  });
}

export function createWorker(
  connection: IORedis,
  env: Env,
  handler: (job: Job<PackageJobData>) => Promise<unknown>,
): Worker<PackageJobData> {
  return new Worker<PackageJobData>(MEDIA_QUEUE, handler, {
    connection,
    concurrency: env.MEDIA_CONCURRENCY,
    // A long lecture can transcode for many minutes without touching Redis; the default lock would
    // expire and the job would be handed to a second worker, transcoding it twice.
    lockDuration: 600_000,
  });
}
