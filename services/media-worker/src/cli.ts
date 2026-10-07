import { basename, extname, resolve } from 'node:path';
import { readFile, stat } from 'node:fs/promises';

import { newId, PrismaClient } from '@tihe/db';

import { loadEnv } from './config.js';
import { ensureWorkDir, Packager } from './packager.js';
import { createQueue, createRedis, PACKAGE_JOB } from './queue.js';
import { Storage } from './storage.js';

/**
 * Package a local video file.
 *
 *   pnpm --filter @tihe/media-worker package ./lecture.mp4 \
 *     --course crs_01… --title "جلسه ۶" [--section sec_01…] [--inline]
 *
 * This is the interface until the admin panel exists (M6).
 *
 * Two routes, and the difference matters:
 *
 *  * `--inline` transcodes in this process, reading the file straight from disk. Nothing is enqueued
 *    and no worker need be running — the common case while developing.
 *  * without it, the file is uploaded to the raw bucket and a job is enqueued. The worker may be on
 *    another machine, so it cannot read your local path; uploading first is what makes the queue
 *    route work at all, and it is the same shape as the LiveKit path in M2b.
 */
interface Args {
  file: string;
  courseId: string;
  title: string;
  sectionId?: string;
  inline: boolean;
}

function parseArgs(argv: string[]): Args {
  const positional: string[] = [];
  const flags = new Map<string, string>();
  let inline = false;

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]!;
    if (arg === '--inline') {
      inline = true;
    } else if (arg.startsWith('--')) {
      const value = argv[i + 1];
      if (value === undefined || value.startsWith('--')) {
        throw new Error(`${arg} needs a value`);
      }
      flags.set(arg.slice(2), value);
      i += 1;
    } else {
      positional.push(arg);
    }
  }

  const file = positional[0];
  const courseId = flags.get('course');
  if (!file || !courseId) {
    throw new Error(
      'usage: package <file.mp4> --course <courseId> [--title "…"] [--section <sectionId>] [--inline]',
    );
  }

  return {
    file: resolve(file),
    courseId,
    // Falling back to the file name beats refusing: a quick test should not need a title argument.
    title: flags.get('title') ?? basename(file).replace(/\.[^.]+$/, ''),
    sectionId: flags.get('section'),
    inline,
  };
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const env = loadEnv();
  await ensureWorkDir(env);

  await stat(args.file); // fail early and clearly if the path is wrong

  const prisma = new PrismaClient();

  try {
    const course = await prisma.course.findUnique({ where: { id: args.courseId } });
    if (!course) throw new Error(`course ${args.courseId} does not exist`);

    if (args.sectionId) {
      const section = await prisma.courseSection.findFirst({
        where: { id: args.sectionId, courseId: args.courseId },
      });
      // Checked rather than trusted: a section belonging to another course would file the lecture
      // where the enrolled students cannot see it.
      if (!section) {
        throw new Error(`section ${args.sectionId} does not belong to course ${args.courseId}`);
      }
    }

    const video = await prisma.video.create({
      data: {
        id: newId('video'),
        courseId: args.courseId,
        sectionId: args.sectionId ?? null,
        title: args.title,
        source: 'upload',
        status: 'processing',
      },
    });

    console.log(`created video ${video.id} — "${video.title}" in ${course.title}`);

    if (args.inline) {
      const packager = new Packager(prisma, new Storage(env), env);
      const result = await packager.package({
        videoId: video.id,
        sourcePath: args.file,
        onProgress: (percent, note) => console.log(`  ${String(percent).padStart(3)}% ${note}`),
      });

      console.log(`\nready: ${result.videoId}`);
      console.log(`  duration    ${Math.round(result.durationMs / 1000)}s`);
      console.log(`  content key ${result.contentKeyId}`);
      for (const r of result.renditions) {
        console.log(
          `  ${r.label.padEnd(6)} ${String(r.segmentCount).padStart(4)} segments  ` +
            `${(r.byteSize / 1_048_576).toFixed(1)} MiB`,
        );
      }
      return;
    }

    // The worker may be on another machine, so a local path is meaningless to it. Upload the source
    // to the raw bucket and enqueue that key instead — which is also what the LiveKit path does, so
    // both routes into the packager look identical from the worker's side.
    const sourceKey = `uploads/${video.id}/source${extname(args.file) || '.mp4'}`;
    const storage = new Storage(env);

    console.log(`uploading to ${storage.rawBucket}/${sourceKey} …`);
    await storage.putBuffer(
      storage.rawBucket,
      sourceKey,
      await readFile(args.file),
      'application/octet-stream',
    );

    const connection = createRedis(env);
    const queue = createQueue(connection);
    const job = await queue.add(PACKAGE_JOB, { videoId: video.id, sourceKey });
    console.log(
      `enqueued job ${job.id} — run "pnpm --filter @tihe/media-worker start" to process it`,
    );
    await queue.close();
    await connection.quit();
  } finally {
    await prisma.$disconnect();
  }
}

void main().catch((error: Error) => {
  console.error(`\n${error.message}`);
  process.exit(1);
});
