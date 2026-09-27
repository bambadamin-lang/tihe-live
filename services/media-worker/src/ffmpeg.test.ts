import { describe, expect, it } from 'vitest';

import {
  AUDIO_RENDITION,
  buildSpriteVtt,
  ladderFor,
  LADDER,
  SPRITE_COLUMNS,
  type ProbeResult,
} from './ffmpeg.js';

const source = (overrides: Partial<ProbeResult> = {}): ProbeResult => ({
  durationMs: 600_000,
  width: 1920,
  height: 1080,
  videoCodec: 'h264',
  audioCodec: 'aac',
  frameRate: 25,
  hasVideo: true,
  hasAudio: true,
  ...overrides,
});

describe('ladderFor', () => {
  it('gives a 1080p source the full ladder plus audio', () => {
    expect(ladderFor(source()).map((r) => r.label)).toEqual(['1080p', '720p', '480p', 'audio']);
  });

  it('never upscales', () => {
    // Encoding a 720p lecture to 1080p costs storage and bandwidth and adds no detail. Class
    // recordings are often 720p or less, so this is the common case, not an edge case.
    expect(ladderFor(source({ width: 1280, height: 720 })).map((r) => r.label)).toEqual([
      '720p',
      '480p',
      'audio',
    ]);
  });

  it('caps a 4K source at the top of the ladder', () => {
    expect(ladderFor(source({ width: 3840, height: 2160 })).map((r) => r.label)).toEqual([
      '1080p',
      '720p',
      '480p',
      'audio',
    ]);
  });

  it('encodes a source smaller than every rung at its own height', () => {
    // A 360p phone recording must be playable, but scaling it up to 480p would be the upscaling the
    // whole function exists to avoid — so it gets a rendition at its native height.
    const ladder = ladderFor(source({ width: 640, height: 360 }));

    expect(ladder.map((r) => r.label)).toEqual(['360p', 'audio']);
    expect(ladder[0]!.height).toBe(360);
  });

  it('omits audio when the source has none', () => {
    // A silent screen recording must not advertise an audio-only variant that contains nothing.
    expect(ladderFor(source({ hasAudio: false })).map((r) => r.label)).not.toContain('audio');
  });

  it('produces audio only for an audio-only source', () => {
    expect(
      ladderFor(source({ hasVideo: false, width: null, height: null })).map((r) => r.label),
    ).toEqual(['audio']);
  });

  it('produces nothing for a file with neither stream', () => {
    // The packager turns this into a clear failure rather than an empty "ready" video.
    expect(ladderFor(source({ hasVideo: false, hasAudio: false }))).toEqual([]);
  });

  it('orders renditions highest quality first', () => {
    const heights = LADDER.map((r) => r.height!);
    expect([...heights].sort((a, b) => b - a)).toEqual(heights);
  });

  it('gives every rung a distinct label and a bitrate that decreases with height', () => {
    const labels = LADDER.map((r) => r.label);
    expect(new Set(labels).size).toBe(labels.length);

    const rates = LADDER.map((r) => r.nominalBps);
    expect([...rates].sort((a, b) => b - a)).toEqual(rates);
    expect(AUDIO_RENDITION.nominalBps).toBeLessThan(rates[rates.length - 1]!);
  });
});

describe('buildSpriteVtt', () => {
  it('maps each interval to a rectangle in the grid', () => {
    const vtt = buildSpriteVtt({ intervalSeconds: 6, durationSeconds: 60, thumbHeight: 90 });

    expect(vtt.startsWith('WEBVTT')).toBe(true);
    // First thumbnail is at the origin.
    expect(vtt).toContain('sprite.jpg#xywh=0,0,160,90');
    // Second is one thumbnail to the right.
    expect(vtt).toContain('sprite.jpg#xywh=160,0,160,90');
  });

  it('wraps to the next row after the grid width', () => {
    const vtt = buildSpriteVtt({ intervalSeconds: 1, durationSeconds: 20, thumbHeight: 90 });
    // Thumbnail index 10 begins row two.
    expect(vtt).toContain(`sprite.jpg#xywh=0,90,160,90`);
  });

  it('formats timestamps as WebVTT requires', () => {
    const vtt = buildSpriteVtt({ intervalSeconds: 6, durationSeconds: 12, thumbHeight: 90 });
    expect(vtt).toMatch(/00:00:00\.000 --> 00:00:06\.000/);
  });

  it('never emits more cues than the grid holds', () => {
    // A three-hour lecture at a one-second interval would otherwise reference tiles that do not
    // exist in the image.
    const vtt = buildSpriteVtt({ intervalSeconds: 1, durationSeconds: 100_000, thumbHeight: 90 });
    const cues = vtt.split('-->').length - 1;
    expect(cues).toBeLessThanOrEqual(SPRITE_COLUMNS * 10);
  });

  it('clamps the last cue to the real duration', () => {
    const vtt = buildSpriteVtt({ intervalSeconds: 10, durationSeconds: 25, thumbHeight: 90 });
    expect(vtt).toContain('00:00:25.000');
  });
});
