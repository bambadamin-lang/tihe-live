import { describe, expect, it } from 'vitest';

import { vodKeys } from './storage.js';

/**
 * The published object layout.
 *
 * This must match `StorageService.vodKeys` in `services/api` exactly: the packager writes these keys
 * and the API presigns them. A divergence produces presigned URLs for objects that do not exist,
 * which surfaces as a 404 mid-playback with nothing in either log to explain it.
 *
 * Duplicated rather than shared because importing it would pull the whole NestJS graph into a worker.
 * These assertions are the seam that keeps the two copies honest — if you change one, this fails.
 */
describe('vodKeys', () => {
  const videoId = 'vid_01J8ZQK5T9XVWR3M2N4P6H8B7C';
  const keys = vodKeys(videoId);

  it('places everything under the video id', () => {
    for (const key of [keys.master, keys.poster, keys.sprite, keys.spriteVtt]) {
      expect(key.startsWith(`${videoId}/`)).toBe(true);
    }
  });

  it('matches the API layout exactly', () => {
    expect(keys.master).toBe(`${videoId}/master.m3u8`);
    expect(keys.poster).toBe(`${videoId}/poster.jpg`);
    expect(keys.sprite).toBe(`${videoId}/sprite.jpg`);
    expect(keys.spriteVtt).toBe(`${videoId}/sprite.vtt`);
    expect(keys.renditionIndex('720p')).toBe(`${videoId}/720p/index.m3u8`);
    expect(keys.segment('720p', 0)).toBe(`${videoId}/720p/seg-00000.ts`);
  });

  it('zero-pads segment numbers to five digits', () => {
    // The padding is what makes segments sort lexically, which both the manifest and any bucket
    // listing rely on.
    expect(keys.segment('720p', 7)).toBe(`${videoId}/720p/seg-00007.ts`);
    expect(keys.segment('720p', 1234)).toBe(`${videoId}/720p/seg-01234.ts`);
    expect(keys.segment('720p', 99999)).toBe(`${videoId}/720p/seg-99999.ts`);
  });

  it('keeps renditions in separate prefixes', () => {
    expect(keys.segment('1080p', 0)).not.toBe(keys.segment('720p', 0));
  });
});
