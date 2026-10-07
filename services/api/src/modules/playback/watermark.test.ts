import { describe, expect, it } from 'vitest';

import { deriveWatermark, newWatermarkSeed, parseWatermark } from './watermark.js';

describe('deriveWatermark', () => {
  const base = {
    phone: '+989123456789',
    userId: 'usr_01J8ZQK5T9XVWR3M2N4P6H8B7C',
    seed: 918273,
  };

  it('never contains the full phone number', () => {
    // A full number burned into a video that then leaks would be a privacy harm we caused.
    const mark = deriveWatermark(base);

    expect(mark.text).not.toContain('9123456789');
    expect(mark.text).not.toContain('345');
  });

  it('includes enough to identify the account from our own records', () => {
    const mark = deriveWatermark(base);

    expect(mark.text).toContain('0912');
    expect(mark.text).toContain('6789');
    expect(mark.text).toContain('H8B7C'.slice(-4));
  });

  it('uses the session seed, so two sessions drift differently', () => {
    // Otherwise an attacker could average the mark away across two recordings.
    const a = deriveWatermark({ ...base, seed: 1 });
    const b = deriveWatermark({ ...base, seed: 2 });

    expect(a.seed).not.toBe(b.seed);
  });

  it('is visible enough to survive both bright and dark frames', () => {
    const mark = deriveWatermark(base);

    expect(mark.opacity).toBeGreaterThanOrEqual(0.2);
    expect(mark.opacity).toBeLessThanOrEqual(0.5);
    expect(mark.fontSize).toBeGreaterThanOrEqual(10);
  });

  it('drifts rather than sitting still', () => {
    // A static mark in a corner is croppable in one pass over a whole recording.
    expect(deriveWatermark(base).movement).toBe('drift');
  });

  it('distinguishes two different users', () => {
    const a = deriveWatermark(base);
    const b = deriveWatermark({ ...base, userId: 'usr_01KAAAAAAAAAAAAAAAAAAAAZZZZ' });

    expect(a.text).not.toBe(b.text);
  });
});

describe('parseWatermark', () => {
  it('reads back a mark it generated', () => {
    // This is the leak-investigation path: read the mark off a leaked video, find the account.
    const mark = deriveWatermark({
      phone: '+989123456789',
      userId: 'usr_01J8ZQK5T9XVWR3M2N4P6H8B7C',
      seed: 1,
    });

    const parsed = parseWatermark(mark.text);

    expect(parsed).toEqual({ maskedPhone: '0912•••6789', idSuffix: 'H8B7C'.slice(-4) });
  });

  it('tolerates surrounding whitespace, since the text is typed in from a video', () => {
    expect(parseWatermark('  0912•••6789 · #8B7C  ')).not.toBeNull();
  });

  it('returns null for text that is not a watermark', () => {
    expect(parseWatermark('just some text')).toBeNull();
    expect(parseWatermark('')).toBeNull();
  });
});

describe('newWatermarkSeed', () => {
  it('produces a positive 32-bit integer', () => {
    const seed = newWatermarkSeed();
    expect(Number.isInteger(seed)).toBe(true);
    expect(seed).toBeGreaterThanOrEqual(0);
    expect(seed).toBeLessThanOrEqual(2_147_483_647);
  });
});
