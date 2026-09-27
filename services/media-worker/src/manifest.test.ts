import { describe, expect, it } from 'vitest';

import { AUDIO_RENDITION, LADDER } from './ffmpeg.js';
import {
  buildMasterPlaylist,
  countSegments,
  isComplete,
  sanitizeMediaPlaylist,
} from './manifest.js';

const ffmpegPlaylist = [
  '#EXTM3U',
  '#EXT-X-VERSION:3',
  '#EXT-X-TARGETDURATION:6',
  '#EXT-X-MEDIA-SEQUENCE:0',
  '#EXT-X-PLAYLIST-TYPE:VOD',
  '#EXTINF:6.000000,',
  'seg-00000.ts',
  '#EXTINF:6.000000,',
  'seg-00001.ts',
  '#EXT-X-ENDLIST',
  '',
].join('\n');

describe('sanitizeMediaPlaylist', () => {
  it('passes a clean playlist through unchanged', () => {
    expect(sanitizeMediaPlaylist(ffmpegPlaylist)).toBe(ffmpegPlaylist);
  });

  it('strips an EXT-X-KEY line', () => {
    // The rule this enforces (CLAUDE.md 3): the key never travels with the media. A manifest with a
    // key URI hands every segment to anyone who can fetch the playlist.
    const withKey = ffmpegPlaylist.replace(
      '#EXTINF:6.000000,',
      '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:6.000000,',
    );

    const cleaned = sanitizeMediaPlaylist(withKey);

    expect(cleaned).not.toContain('EXT-X-KEY');
    expect(countSegments(cleaned)).toBe(2);
  });

  it('throws rather than publish a key reference it cannot strip', () => {
    // A key mentioned somewhere other than the start of a line means the format changed under us.
    // Failing the job is the only safe response; publishing is irreversible.
    expect(() => sanitizeMediaPlaylist('#EXTM3U\n#EXTINF:6,\nEXT-X-KEY-ish.ts')).toThrow(
      /EXT-X-KEY/,
    );
  });
});

describe('countSegments', () => {
  it('counts segment lines only', () => {
    expect(countSegments(ffmpegPlaylist)).toBe(2);
  });

  it('is zero for a playlist with no segments', () => {
    expect(countSegments('#EXTM3U\n#EXT-X-ENDLIST')).toBe(0);
  });
});

describe('isComplete', () => {
  it('recognises a finished VOD playlist', () => {
    expect(isComplete(ffmpegPlaylist)).toBe(true);
    expect(isComplete(ffmpegPlaylist.replace('#EXT-X-ENDLIST', ''))).toBe(false);
  });
});

describe('buildMasterPlaylist', () => {
  it('lists every rendition with bandwidth and resolution', () => {
    const master = buildMasterPlaylist([
      { spec: LADDER[0]!, width: 1920, height: 1080 },
      { spec: LADDER[1]!, width: 1280, height: 720 },
    ]);

    expect(master).toContain('1080p/index.m3u8');
    expect(master).toContain('720p/index.m3u8');
    expect(master).toContain('RESOLUTION=1920x1080');
    expect(master).toContain(`BANDWIDTH=${LADDER[0]!.nominalBps}`);
  });

  it('advertises audio-only without a resolution', () => {
    const master = buildMasterPlaylist([{ spec: AUDIO_RENDITION, width: null, height: null }]);

    expect(master).toContain('audio/index.m3u8');
    expect(master).not.toContain('RESOLUTION');
    expect(master).toContain('mp4a.40.2');
  });

  it('never contains a key line', () => {
    const master = buildMasterPlaylist([{ spec: LADDER[0]!, width: 1920, height: 1080 }]);
    expect(master).not.toContain('EXT-X-KEY');
  });

  it('starts with the EXTM3U tag and ends with a newline', () => {
    // A playlist missing either is rejected by strict players.
    const master = buildMasterPlaylist([{ spec: LADDER[2]!, width: 854, height: 480 }]);
    expect(master.startsWith('#EXTM3U\n')).toBe(true);
    expect(master.endsWith('\n')).toBe(true);
  });
});
