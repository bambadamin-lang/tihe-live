/**
 * Development seed.
 *
 * Creates enough to exercise the whole student path: a term, a published course, sections, videos
 * with renditions and content keys, an enrolled student, a teacher, and an admin.
 *
 * The content keys are real — generated and wrapped with the configured KEK — so the playback
 * endpoint returns a genuinely wrapped key and the client-side unwrap can be tested. The segments
 * those keys would decrypt do not exist until media-worker is built (M2), so playback will fetch a
 * manifest that is not there. That is expected at M0 and better than seeding a fake key that makes
 * the crypto path untestable.
 */
import { randomBytes } from 'node:crypto';

import { PrismaClient } from '@prisma/client';
import { createCipheriv } from 'node:crypto';
import { ulid } from 'ulid';

const prisma = new PrismaClient();

const id = (prefix: string) => `${prefix}_${ulid()}`;

/** Mirrors PlaybackService.wrapContentKeyWithKek — kept inline so the seed has no Nest dependency. */
function wrapWithKek(cek: Buffer, kekBase64: string): string {
  const kek = Buffer.from(kekBase64, 'base64');
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', kek, iv);
  const ciphertext = Buffer.concat([cipher.update(cek), cipher.final()]);
  return Buffer.concat([iv, ciphertext, cipher.getAuthTag()]).toString('base64');
}

async function main() {
  const kek = process.env.KEK_BASE64;
  if (!kek) {
    throw new Error(
      'KEK_BASE64 is required to seed. Run ./infra/scripts/generate-secrets.sh and fill services/api/.env',
    );
  }

  console.log('seeding…');

  // ── People ──
  // Phone numbers in the 0912555xxxx range so they are obviously fixtures.
  const admin = await prisma.user.upsert({
    where: { phone: '+989125550001' },
    update: {},
    create: {
      id: id('usr'),
      phone: '+989125550001',
      displayName: 'مدیر سامانه',
      role: 'admin',
    },
  });

  const teacher = await prisma.user.upsert({
    where: { phone: '+989125550002' },
    update: {},
    create: {
      id: id('usr'),
      phone: '+989125550002',
      displayName: 'دکتر رضایی',
      role: 'teacher',
    },
  });

  const student = await prisma.user.upsert({
    where: { phone: '+989125550003' },
    update: {},
    create: {
      id: id('usr'),
      phone: '+989125550003',
      displayName: 'دانشجوی نمونه',
      role: 'student',
    },
  });

  // ── Term and course ──
  const term = await prisma.term.create({
    data: {
      id: id('trm'),
      title: 'نیمسال اول ۱۴۰۵-۱۴۰۶',
      startsAt: new Date('2026-09-22T00:00:00Z'),
      endsAt: new Date('2027-01-20T00:00:00Z'),
      isCurrent: true,
    },
  });

  const course = await prisma.course.create({
    data: {
      id: id('crs'),
      termId: term.id,
      title: 'ریاضی عمومی ۱',
      slug: `riazi-1-${ulid().slice(-6).toLowerCase()}`,
      description: 'حد، پیوستگی، مشتق و کاربردهای آن برای دانشجویان مهندسی.',
      status: 'published',
      teacherId: teacher.id,
      allowDownload: true,
      allowCapture: false,
      offlineWindowDays: 30,
      maxDevices: 2,
      maxConcurrentStreams: 1,
    },
  });

  // A second course with stricter policy, so device and download limits can be exercised.
  const strictCourse = await prisma.course.create({
    data: {
      id: id('crs'),
      termId: term.id,
      title: 'مبانی برنامه‌نویسی',
      slug: `mabani-barnamenevisi-${ulid().slice(-6).toLowerCase()}`,
      description: 'الگوریتم، ساختار داده و برنامه‌نویسی به زبان پایتون.',
      status: 'published',
      teacherId: teacher.id,
      allowDownload: false, // exercises DOWNLOAD_NOT_ALLOWED
      allowCapture: false,
      offlineWindowDays: 7,
      maxDevices: 1, // exercises DEVICE_LIMIT_REACHED
      maxConcurrentStreams: 1,
    },
  });

  const section = await prisma.courseSection.create({
    data: { id: id('sec'), courseId: course.id, title: 'فصل ۱ — حد و پیوستگی', order: 1 },
  });

  const section2 = await prisma.courseSection.create({
    data: { id: id('sec'), courseId: course.id, title: 'فصل ۲ — مشتق', order: 2 },
  });

  // ── Videos ──
  const videoSpecs = [
    { title: 'جلسه ۱ — مفهوم حد', sectionId: section.id, minutes: 88 },
    { title: 'جلسه ۲ — قضایای حد', sectionId: section.id, minutes: 92 },
    { title: 'جلسه ۳ — پیوستگی توابع', sectionId: section.id, minutes: 79 },
    { title: 'جلسه ۴ — مشتق توابع مرکب', sectionId: section2.id, minutes: 95 },
    { title: 'جلسه ۵ — کاربردهای مشتق', sectionId: section2.id, minutes: 84 },
  ];

  for (const [index, spec] of videoSpecs.entries()) {
    const videoId = id('vid');
    const durationMs = spec.minutes * 60 * 1000;
    const segmentCount = Math.ceil(durationMs / 6000);

    await prisma.video.create({
      data: {
        id: videoId,
        courseId: course.id,
        sectionId: spec.sectionId,
        title: spec.title,
        description: `ضبط کلاس زنده ${spec.title}.`,
        source: 'live_recording',
        status: 'ready',
        durationMs,
        posterKey: `${videoId}/poster.jpg`,
        spriteKey: `${videoId}/sprite.jpg`,
        recordedAt: new Date(Date.now() - (videoSpecs.length - index) * 7 * 86_400_000),
        publishedAt: new Date(Date.now() - (videoSpecs.length - index) * 7 * 86_400_000),
        assets: {
          create: [
            {
              id: id('ast'),
              label: '1080p',
              storageKey: `${videoId}/1080p/index.m3u8`,
              width: 1920,
              height: 1080,
              bitrate: 4_500_000,
              codec: 'h264',
              segmentCount,
              targetDuration: 6,
              byteSize: BigInt(Math.round((4_500_000 / 8) * (durationMs / 1000))),
            },
            {
              id: id('ast'),
              label: '720p',
              storageKey: `${videoId}/720p/index.m3u8`,
              width: 1280,
              height: 720,
              bitrate: 1_800_000,
              codec: 'h264',
              segmentCount,
              targetDuration: 6,
              byteSize: BigInt(Math.round((1_800_000 / 8) * (durationMs / 1000))),
            },
            {
              id: id('ast'),
              label: 'audio',
              storageKey: `${videoId}/audio/index.m3u8`,
              width: null,
              height: null,
              bitrate: 64_000,
              codec: 'aac',
              segmentCount,
              targetDuration: 6,
              byteSize: BigInt(Math.round((64_000 / 8) * (durationMs / 1000))),
            },
          ],
        },
        contentKeys: {
          create: [
            {
              id: id('ck'),
              // A real key, really wrapped, so the playback path returns something the client can
              // genuinely attempt to unwrap.
              wrappedKey: wrapWithKek(randomBytes(16), kek),
              keyVersion: 1,
              algorithm: 'AES-128-CTR',
            },
          ],
        },
        chapters: {
          create: [
            { id: id('chp'), title: 'مقدمه', startMs: 0, order: 0 },
            {
              id: id('chp'),
              title: 'مثال‌های حل‌شده',
              startMs: Math.round(durationMs * 0.3),
              order: 1,
            },
            { id: id('chp'), title: 'جمع‌بندی', startMs: Math.round(durationMs * 0.85), order: 2 },
          ],
        },
      },
    });
  }

  // One video still processing, so the client's VIDEO_NOT_READY path is reachable.
  await prisma.video.create({
    data: {
      id: id('vid'),
      courseId: strictCourse.id,
      title: 'جلسه ۱ — متغیرها و انواع داده',
      source: 'live_recording',
      status: 'processing',
      durationMs: 0,
    },
  });

  // ── Enrollments ──
  for (const courseId of [course.id, strictCourse.id]) {
    await prisma.enrollment.upsert({
      where: { userId_courseId: { userId: student.id, courseId } },
      update: { status: 'active' },
      create: { id: id('enr'), userId: student.id, courseId, status: 'active' },
    });
  }

  console.log('\nseeded:');
  console.log(`  term     ${term.title}`);
  console.log(`  courses  ${course.title} (2 sections, 5 videos)`);
  console.log(`           ${strictCourse.title} (downloads off, 1 device)`);
  console.log('\nsign in with any of these — the OTP prints to the API log:');
  console.log(`  student  09125550003  (${student.id})`);
  console.log(`  teacher  09125550002  (${teacher.id})`);
  console.log(`  admin    09125550001  (${admin.id})`);
  console.log('\nNote: video segments do not exist yet — media-worker arrives in M2. Catalog,');
  console.log('search, progress and licence issuing are fully exercisable now.');
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
