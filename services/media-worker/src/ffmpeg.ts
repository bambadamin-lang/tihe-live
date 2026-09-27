import { spawn } from 'node:child_process';
import { mkdir, readdir, stat } from 'node:fs/promises';
import { join } from 'node:path';

/**
 * ffmpeg and ffprobe wrappers.
 *
 * Everything here shells out rather than using a binding: ffmpeg's CLI is the stable interface, the
 * bindings lag it, and a lecture transcode is minutes long so process overhead is irrelevant.
 */

export class FfmpegError extends Error {
  constructor(
    message: string,
    readonly stderrTail: string,
  ) {
    super(message);
    this.name = 'FfmpegError';
  }
}

async function run(command: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ['ignore', 'pipe', 'pipe'] });

    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk: Buffer) => {
      stdout += chunk.toString();
    });
    child.stderr.on('data', (chunk: Buffer) => {
      stderr += chunk.toString();
      // ffmpeg is extremely chatty on stderr; only the tail is ever useful in a failure report.
      if (stderr.length > 8000) stderr = stderr.slice(-8000);
    });

    child.on('error', (error) =>
      reject(new FfmpegError(`${command} could not be started: ${error.message}`, stderr)),
    );
    child.on('close', (code) => {
      if (code === 0) return resolve(stdout);
      reject(new FfmpegError(`${command} exited with code ${code}`, stderr));
    });
  });
}

export interface ProbeResult {
  durationMs: number;
  width: number | null;
  height: number | null;
  videoCodec: string | null;
  audioCodec: string | null;
  frameRate: number;
  hasVideo: boolean;
  hasAudio: boolean;
}

/**
 * Inspects a source file.
 *
 * A file that fails here must fail the whole job. The alternative — packaging it anyway — produces a
 * video marked `ready` that no player can open, and the student reports "it does not work" with no
 * trace of why.
 */
export async function probe(path: string): Promise<ProbeResult> {
  const raw = await run('ffprobe', [
    '-v',
    'error',
    '-print_format',
    'json',
    '-show_format',
    '-show_streams',
    path,
  ]);

  const parsed = JSON.parse(raw) as {
    format?: { duration?: string };
    streams?: Array<{
      codec_type?: string;
      codec_name?: string;
      width?: number;
      height?: number;
      avg_frame_rate?: string;
    }>;
  };

  const streams = parsed.streams ?? [];
  const video = streams.find((s) => s.codec_type === 'video');
  const audio = streams.find((s) => s.codec_type === 'audio');

  // avg_frame_rate arrives as a rational like "30000/1001".
  const [num, den] = (video?.avg_frame_rate ?? '25/1').split('/').map(Number);
  const frameRate = den && den !== 0 ? (num ?? 25) / den : 25;

  return {
    durationMs: Math.round(Number(parsed.format?.duration ?? 0) * 1000),
    width: video?.width ?? null,
    height: video?.height ?? null,
    videoCodec: video?.codec_name ?? null,
    audioCodec: audio?.codec_name ?? null,
    frameRate: Number.isFinite(frameRate) && frameRate > 0 ? frameRate : 25,
    hasVideo: video !== undefined,
    hasAudio: audio !== undefined,
  };
}

export interface RenditionSpec {
  label: string;
  height: number | null;
  /** Constant Rate Factor. Lower is better quality and larger. */
  crf: number;
  /** Ceiling in bits per second, so a busy scene cannot blow the bitrate budget. */
  maxrateBps: number;
  audioBps: number;
  /** Nominal bitrate recorded on the asset row and advertised in the master playlist. */
  nominalBps: number;
}

/** The full ladder, highest first. What a given source actually gets comes from `ladderFor`. */
export const LADDER: RenditionSpec[] = [
  {
    label: '1080p',
    height: 1080,
    crf: 23,
    maxrateBps: 4_500_000,
    audioBps: 128_000,
    nominalBps: 4_500_000,
  },
  {
    label: '720p',
    height: 720,
    crf: 24,
    maxrateBps: 1_800_000,
    audioBps: 128_000,
    nominalBps: 1_800_000,
  },
  {
    label: '480p',
    height: 480,
    crf: 26,
    maxrateBps: 900_000,
    audioBps: 96_000,
    nominalBps: 900_000,
  },
];

/** Audio-only, for students on a connection that cannot carry video. */
export const AUDIO_RENDITION: RenditionSpec = {
  label: 'audio',
  height: null,
  crf: 0,
  maxrateBps: 0,
  audioBps: 64_000,
  nominalBps: 64_000,
};

export const SEGMENT_SECONDS = 6;

/**
 * Chooses renditions for a source.
 *
 * **Never upscales.** Encoding a 720p lecture to 1080p costs storage and bandwidth and cannot add
 * detail that was not captured — and a class recorded on a laptop camera is often 720p or less. The
 * lowest rung is always included so there is something playable on a poor connection, even if the
 * source is smaller than it.
 */
export function ladderFor(probe: ProbeResult): RenditionSpec[] {
  if (!probe.hasVideo) return probe.hasAudio ? [AUDIO_RENDITION] : [];

  const sourceHeight = probe.height ?? 0;
  const video = LADDER.filter((r) => r.height !== null && r.height <= sourceHeight);

  // A source shorter than every rung — a 360p phone recording — still needs one video rendition, but
  // scaling it up to the lowest rung would be the upscaling this function exists to avoid. Encode it
  // at its own height instead, borrowing the lowest rung's quality settings, and label it by that
  // height so the storage path stays self-describing.
  if (video.length === 0 && sourceHeight > 0) {
    const lowest = LADDER[LADDER.length - 1]!;
    video.push({ ...lowest, label: `${sourceHeight}p`, height: sourceHeight });
  }

  return probe.hasAudio ? [...video, AUDIO_RENDITION] : video;
}

/**
 * Transcodes one rendition into HLS with MPEG-TS segments.
 *
 * Returns the directory holding `index.m3u8` and `seg-NNNNN.ts`. The segments are **plaintext at
 * this point** — the caller encrypts them before upload, and must remove this directory afterwards.
 *
 * Two flag groups deserve explanation:
 *
 *  * `-force_key_frames` with `-sc_threshold 0` puts a keyframe at the start of every segment.
 *    Without it ffmpeg places keyframes on scene changes, segments stop being independently
 *    decodable, and seeking breaks — which matters doubly here because the loopback server serves
 *    one segment at a time.
 *  * capped CRF (`-crf` with `-maxrate`/`-bufsize`) instead of a fixed bitrate. Lecture content is
 *    mostly static slides, where CRF spends a fraction of the bits for the same perceived quality;
 *    the cap stops a busy screen-share from exceeding what a student's connection can carry.
 */
export async function transcodeRendition(options: {
  sourcePath: string;
  outputDir: string;
  spec: RenditionSpec;
  frameRate: number;
}): Promise<{ dir: string; segmentCount: number; byteSize: number }> {
  const { sourcePath, outputDir, spec, frameRate } = options;
  await mkdir(outputDir, { recursive: true });

  const gop = Math.max(1, Math.round(frameRate * SEGMENT_SECONDS));

  const common = ['-hide_banner', '-loglevel', 'error', '-y', '-i', sourcePath];

  const hls = [
    '-f',
    'hls',
    '-hls_time',
    String(SEGMENT_SECONDS),
    // 0 keeps every segment in the playlist: this is VOD, not a live window.
    '-hls_list_size',
    '0',
    '-hls_playlist_type',
    'vod',
    '-hls_segment_type',
    'mpegts',
    '-hls_segment_filename',
    join(outputDir, 'seg-%05d.ts'),
    join(outputDir, 'index.m3u8'),
  ];

  const args =
    spec.label === 'audio'
      ? [...common, '-vn', '-c:a', 'aac', '-b:a', String(spec.audioBps), '-ac', '1', ...hls]
      : [
          ...common,
          '-c:v',
          'libx264',
          // `main` rather than `high`: still hardware-decodable on the older Android devices a
          // student body actually owns, at a negligible size cost for this content.
          '-profile:v',
          'main',
          '-preset',
          'medium',
          '-crf',
          String(spec.crf),
          '-maxrate',
          String(spec.maxrateBps),
          '-bufsize',
          String(spec.maxrateBps * 2),
          '-vf',
          `scale=-2:${spec.height}`,
          '-g',
          String(gop),
          '-keyint_min',
          String(gop),
          '-sc_threshold',
          '0',
          '-force_key_frames',
          `expr:gte(t,n_forced*${SEGMENT_SECONDS})`,
          '-c:a',
          'aac',
          '-b:a',
          String(spec.audioBps),
          ...hls,
        ];

  await run('ffmpeg', args);

  const files = (await readdir(outputDir)).filter((f) => f.endsWith('.ts')).sort();
  let byteSize = 0;
  for (const file of files) {
    byteSize += (await stat(join(outputDir, file))).size;
  }

  if (files.length === 0) {
    throw new FfmpegError(`rendition ${spec.label} produced no segments`, '');
  }

  return { dir: outputDir, segmentCount: files.length, byteSize };
}

/** A single frame for the course/video card. */
export async function extractPoster(options: {
  sourcePath: string;
  outputPath: string;
  atSeconds: number;
}): Promise<void> {
  await run('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-ss',
    String(options.atSeconds),
    '-i',
    options.sourcePath,
    '-frames:v',
    '1',
    '-vf',
    'scale=1280:-2',
    '-q:v',
    '3',
    options.outputPath,
  ]);
}

export const SPRITE_COLUMNS = 10;
export const SPRITE_ROWS = 10;
export const SPRITE_THUMB_WIDTH = 160;

/**
 * Builds a thumbnail grid plus its WebVTT index, for scrub previews.
 *
 * One image rather than N requests: a 100-thumbnail sprite is a single fetch, where 100 separate
 * images would be 100 round trips during a scrub. The WebVTT maps each time range to a rectangle.
 */
export async function buildSprite(options: {
  sourcePath: string;
  outputPath: string;
  durationMs: number;
}): Promise<{ vtt: string; intervalSeconds: number; thumbHeight: number }> {
  const tiles = SPRITE_COLUMNS * SPRITE_ROWS;
  const durationSeconds = Math.max(1, options.durationMs / 1000);
  const intervalSeconds = Math.max(1, durationSeconds / tiles);

  await run('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    options.sourcePath,
    '-vf',
    `fps=1/${intervalSeconds},scale=${SPRITE_THUMB_WIDTH}:-2,tile=${SPRITE_COLUMNS}x${SPRITE_ROWS}`,
    '-frames:v',
    '1',
    '-q:v',
    '4',
    options.outputPath,
  ]);

  // Derived from the sprite's real dimensions so the VTT cannot disagree with the image.
  const probed = await probe(options.outputPath);
  const thumbHeight = Math.round((probed.height ?? 0) / SPRITE_ROWS);

  return {
    vtt: buildSpriteVtt({ intervalSeconds, durationSeconds, thumbHeight }),
    intervalSeconds,
    thumbHeight,
  };
}

export function buildSpriteVtt(options: {
  intervalSeconds: number;
  durationSeconds: number;
  thumbHeight: number;
}): string {
  const { intervalSeconds, durationSeconds, thumbHeight } = options;
  const lines = ['WEBVTT', ''];

  const count = Math.min(
    SPRITE_COLUMNS * SPRITE_ROWS,
    Math.ceil(durationSeconds / intervalSeconds),
  );

  for (let i = 0; i < count; i += 1) {
    const from = i * intervalSeconds;
    const to = Math.min((i + 1) * intervalSeconds, durationSeconds);
    const x = (i % SPRITE_COLUMNS) * SPRITE_THUMB_WIDTH;
    const y = Math.floor(i / SPRITE_COLUMNS) * thumbHeight;

    lines.push(`${vttTime(from)} --> ${vttTime(to)}`);
    lines.push(`sprite.jpg#xywh=${x},${y},${SPRITE_THUMB_WIDTH},${thumbHeight}`);
    lines.push('');
  }

  return lines.join('\n');
}

function vttTime(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);
  const millis = Math.round((seconds - Math.floor(seconds)) * 1000);
  const pad = (n: number, width = 2) => String(n).padStart(width, '0');
  return `${pad(hours)}:${pad(minutes)}:${pad(secs)}.${pad(millis, 3)}`;
}
