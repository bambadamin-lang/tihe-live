import { describe, expect, it } from 'vitest';

import {
  effectiveDeviceLimit,
  hasFreeSlot,
  isSignedIn,
  type DeviceSessionState,
} from './sessions.js';

const now = new Date('2026-10-04T10:00:00Z');
const later = (ms: number) => new Date(now.getTime() + ms);

const signedIn: DeviceSessionState = {
  sessionId: 'ses-a',
  sessionExpiresAt: later(60_000),
  revokedAt: null,
};

describe('isSignedIn', () => {
  it('is true for a live session', () => {
    expect(isSignedIn(signedIn, now)).toBe(true);
  });

  it('is false once signed out', () => {
    expect(isSignedIn({ ...signedIn, sessionId: null, sessionExpiresAt: null }, now)).toBe(false);
  });

  it('is false once the session has timed out, to the millisecond', () => {
    expect(isSignedIn({ ...signedIn, sessionExpiresAt: later(1) }, now)).toBe(true);
    expect(isSignedIn({ ...signedIn, sessionExpiresAt: now }, now)).toBe(false);
    expect(isSignedIn({ ...signedIn, sessionExpiresAt: later(-1) }, now)).toBe(false);
  });

  it('is false for a revoked device even with a session row', () => {
    expect(isSignedIn({ ...signedIn, revokedAt: later(-1000) }, now)).toBe(false);
  });
});

describe('effectiveDeviceLimit', () => {
  it("uses the account's own limit when an admin set one", () => {
    expect(effectiveDeviceLimit(1, 3)).toBe(1);
    expect(effectiveDeviceLimit(5, 3)).toBe(5);
  });

  it('falls back to the institute default', () => {
    expect(effectiveDeviceLimit(null, 3)).toBe(3);
  });
});

describe('hasFreeSlot', () => {
  const out = { ...signedIn, sessionId: null, sessionExpiresAt: null };
  const expired = { ...signedIn, sessionExpiresAt: later(-1) };

  it('refuses when the other signed-in devices fill the limit', () => {
    expect(hasFreeSlot([signedIn, signedIn], 2, now)).toBe(false);
  });

  it('allows when one of them signs out or times out', () => {
    expect(hasFreeSlot([signedIn, out], 2, now)).toBe(true);
    expect(hasFreeSlot([signedIn, expired], 2, now)).toBe(true);
  });

  it('allows a first device at limit 1', () => {
    expect(hasFreeSlot([], 1, now)).toBe(true);
    expect(hasFreeSlot([signedIn], 1, now)).toBe(false);
  });

  it('applies a lowered limit to the next sign-in only', () => {
    // Three already signed in, limit lowered to 2: nobody is signed out, but a fourth cannot join.
    expect(hasFreeSlot([signedIn, signedIn, signedIn], 2, now)).toBe(false);
  });
});
