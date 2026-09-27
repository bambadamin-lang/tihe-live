import { PrismaClient } from '@tihe/db';

import { loadEnv } from './config.js';
import { ensureWorkDir, Packager } from './packager.js';
import { createRedis, createWorker, PACKAGE_JOB, type PackageJobData } from './queue.js';
import { Storage } from './storage.js';

/**
 * The media worker process.
 *
 * Runs separately from the API on purpose: ffmpeg saturates a core for minutes at a time, and sharing
 * a process with the API would make every request slow while a lecture is transcoding.
 */
async function main(): Promise<void> {
  const env = loadEnv();
  await ensureWorkDir(env);

  const prisma = new PrismaClient();
  const storage = new Storage(env);
  const packager = new Packager(prisma, storage, env);
  const connection = createRedis(env);

  const worker = createWorker(connection, env, async (job) => {
    if (job.name !== PACKAGE_JOB) {
      console.warn(`ignoring unknown job "${job.name}"`);
      return;
    }

    const data = job.data as PackageJobData;
    if (!data.sourceKey) {
      // A queued job has no access to anyone's local disk, so the source must be in the raw bucket.
      // Failing here names the problem; letting it reach the packager reports it as a missing
      // argument, which sounds like a bug rather than a malformed job.
      throw new Error(
        `job ${job.id} for ${data.videoId} has no sourceKey — a queued job needs its source in the raw bucket`,
      );
    }
    console.log(`[${job.id}] packaging ${data.videoId} from ${data.sourceKey}`);

    const result = await packager.package({
      videoId: data.videoId,
      sourceKey: data.sourceKey,
      onProgress: (percent, note) => {
        void job.updateProgress(percent);
        console.log(`[${job.id}] ${percent}% ${note}`);
      },
    });

    console.log(
      `[${job.id}] ${result.skipped ? 'already packaged' : 'packaged'} ${result.videoId}: ` +
        result.renditions.map((r) => `${r.label}/${r.segmentCount}seg`).join(' '),
    );
    return result;
  });

  worker.on('failed', (job, error) => {
    // The video row is already marked failed by the packager; this is the operator-facing record.
    console.error(`[${job?.id}] failed: ${error.message}`);
  });

  // A signal sent to the process group arrives more than once, and a second shutdown while the first
  // is still closing the worker throws on an already-closed connection.
  let shuttingDown = false;

  const shutdown = async (signal: string): Promise<void> => {
    if (shuttingDown) return;
    shuttingDown = true;

    // Closing the worker lets an in-flight transcode finish rather than orphaning a half-uploaded
    // rendition, which idempotency would then have to repair.
    console.log(`${signal} received, finishing current job…`);
    try {
      await worker.close();
      // BullMQ may already have closed the shared connection as part of worker.close().
      if (connection.status !== 'end') await connection.quit();
      await prisma.$disconnect();
    } catch (error) {
      console.error(`shutdown did not complete cleanly: ${(error as Error).message}`);
    }
    process.exit(0);
  };

  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT', () => void shutdown('SIGINT'));

  console.log(
    `media-worker ready (concurrency ${env.MEDIA_CONCURRENCY}, work dir ${env.MEDIA_WORK_DIR})`,
  );
}

void main().catch((error) => {
  console.error(error);
  process.exit(1);
});
