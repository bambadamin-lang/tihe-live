import { readFile } from 'node:fs/promises';

import { AUDIO_RENDITION, SEGMENT_SECONDS, type RenditionSpec } from './ffmpeg.js';

/**
 * HLS manifest construction.
 *
 * The one rule that matters: **no `#EXT-X-KEY` line, ever** (CLAUDE.md rule 3). The segments these
 * manifests point at are encrypted, but the key does not travel with the media — it is delivered
 * wrapped to one device, and `secure-core` rewrites the manifest for the local player anyway. A
 * manifest carrying a key URI would hand every segment to anyone who could fetch the playlist.
 *
 * A consequence worth knowing: a normal HLS player handed one of these manifests will download
 * segments and fail to decode them. That is intended, not a bug.
 */

/** Strips any key line ffmpeg might have written, and asserts the result is clean. */
export function sanitizeMediaPlaylist(raw: string): string {
  const cleaned = raw
    .split('\n')
    .filter((line) => !line.startsWith('#EXT-X-KEY'))
    .join('\n');

  if (cleaned.includes('EXT-X-KEY')) {
    // Belt and braces. If this ever throws, the packager is about to publish a key alongside the
    // media, and failing the job is the only correct response.
    throw new Error('refusing to publish a manifest containing an EXT-X-KEY line');
  }
  return cleaned;
}

export async function readMediaPlaylist(path: string): Promise<string> {
  return sanitizeMediaPlaylist(await readFile(path, 'utf8'));
}

export interface MasterEntry {
  spec: RenditionSpec;
  width: number | null;
  height: number | null;
}

/**
 * Builds the multi-variant playlist.
 *
 * Audio-only is advertised as a separate low-bandwidth variant rather than an `EXT-X-MEDIA`
 * alternate group: it is a deliberate choice a student on a poor connection makes, not an audio
 * track to be paired with video.
 */
export function buildMasterPlaylist(entries: MasterEntry[]): string {
  const lines = ['#EXTM3U', '#EXT-X-VERSION:3'];

  for (const { spec, width, height } of entries) {
    if (spec.label === AUDIO_RENDITION.label) {
      lines.push(
        `#EXT-X-STREAM-INF:BANDWIDTH=${spec.nominalBps},CODECS="mp4a.40.2"`,
        `${spec.label}/index.m3u8`,
      );
      continue;
    }

    const resolution = width && height ? `,RESOLUTION=${width}x${height}` : '';
    lines.push(
      `#EXT-X-STREAM-INF:BANDWIDTH=${spec.nominalBps}${resolution},CODECS="avc1.4d401f,mp4a.40.2"`,
      `${spec.label}/index.m3u8`,
    );
  }

  return `${lines.join('\n')}\n`;
}

/** Segments per rendition, as the manifest declares them. Used to cross-check the asset row. */
export function countSegments(mediaPlaylist: string): number {
  return mediaPlaylist.split('\n').filter((l) => l.trim().endsWith('.ts')).length;
}

export function isComplete(mediaPlaylist: string): boolean {
  return mediaPlaylist.includes('#EXT-X-ENDLIST');
}

export { SEGMENT_SECONDS };
