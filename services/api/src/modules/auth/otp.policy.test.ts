import { describe, expect, it } from 'vitest';

import {
  checkOtpState,
  decideOtpRequest,
  generateOtpCode,
  type OtpPolicyConfig,
} from './otp.policy.js';

const config: OtpPolicyConfig = {
  ttlSeconds: 120,
  resendAfterSeconds: 60,
  maxPerPhonePerHour: 5,
  maxPerIpPerHour: 20,
  maxAttempts: 5,
};

const now = new Date('2026-09-27T12:00:00Z');
const agoSeconds = (s: number) => new Date(now.getTime() - s * 1000);
const record = (createdAt: Date, consumedAt: Date | null = null) => ({ createdAt, consumedAt });

describe('decideOtpRequest', () => {
  it('allows a first request', () => {
    expect(decideOtpRequest(now, config, [], 0)).toEqual({ allowed: true });
  });

  it('blocks a resend inside the cooldown and says how long to wait', () => {
    // The "didn't arrive, tap again" loop is the single biggest source of wasted SMS spend.
    const decision = decideOtpRequest(now, config, [record(agoSeconds(20))], 0);

    expect(decision).toEqual({
      allowed: false,
      reason: 'resend_too_soon',
      retryAfterSeconds: 40,
    });
  });

  it('allows a resend once the cooldown has passed', () => {
    expect(decideOtpRequest(now, config, [record(agoSeconds(61))], 0)).toEqual({ allowed: true });
  });

  it('blocks once the hourly limit for a phone is reached', () => {
    const history = [300, 600, 900, 1200, 1500].map((s) => record(agoSeconds(s)));

    expect(decideOtpRequest(now, config, history, 0)).toEqual({
      allowed: false,
      reason: 'phone_hourly_limit',
    });
  });

  it('ignores requests older than an hour when counting', () => {
    const history = [3700, 4000, 5000, 6000, 7000].map((s) => record(agoSeconds(s)));

    expect(decideOtpRequest(now, config, history, 0)).toEqual({ allowed: true });
  });

  it('blocks once the hourly limit for an IP is reached', () => {
    // The per-phone cooldown does nothing against a script walking through many numbers, which is
    // how an attacker would enumerate the institute's students.
    expect(decideOtpRequest(now, config, [], 20)).toEqual({
      allowed: false,
      reason: 'ip_hourly_limit',
    });
  });

  it('applies the cooldown before the hourly limits', () => {
    // A user hammering the button should be told to wait, not that they are rate limited for an
    // hour — the recovery advice differs.
    const history = [10, 300, 600, 900, 1200].map((s) => record(agoSeconds(s)));
    const decision = decideOtpRequest(now, config, history, 0);

    expect(decision.allowed).toBe(false);
    expect(decision).toHaveProperty('reason', 'resend_too_soon');
  });
});

describe('checkOtpState', () => {
  it('permits a hash check for a fresh code', () => {
    expect(
      checkOtpState(now, config, {
        expiresAt: new Date(now.getTime() + 60_000),
        consumedAt: null,
        attemptCount: 0,
      }),
    ).toBe('check_hash');
  });

  it('rejects an expired code', () => {
    expect(
      checkOtpState(now, config, {
        expiresAt: agoSeconds(1),
        consumedAt: null,
        attemptCount: 0,
      }),
    ).toBe('expired');
  });

  it('rejects a code that was already used', () => {
    // Without this, one intercepted code would work repeatedly.
    expect(
      checkOtpState(now, config, {
        expiresAt: new Date(now.getTime() + 60_000),
        consumedAt: agoSeconds(5),
        attemptCount: 1,
      }),
    ).toBe('consumed');
  });

  it('locks out after too many attempts', () => {
    // A 5-digit code is 100k possibilities; without a lockout, brute force is minutes of work.
    expect(
      checkOtpState(now, config, {
        expiresAt: new Date(now.getTime() + 60_000),
        consumedAt: null,
        attemptCount: 5,
      }),
    ).toBe('too_many_attempts');
  });

  it('checks consumption before expiry', () => {
    // A consumed code that also expired should report consumption: it is the more precise fact.
    expect(
      checkOtpState(now, config, {
        expiresAt: agoSeconds(10),
        consumedAt: agoSeconds(20),
        attemptCount: 1,
      }),
    ).toBe('consumed');
  });

  it('checks the attempt count before comparing hashes', () => {
    // Order matters: a locked record must not spend CPU on Argon2, and must not leak timing that
    // distinguishes a wrong code from a locked one.
    expect(
      checkOtpState(now, config, {
        expiresAt: agoSeconds(10),
        consumedAt: null,
        attemptCount: 99,
      }),
    ).toBe('too_many_attempts');
  });
});

describe('generateOtpCode', () => {
  it('produces the requested number of digits', () => {
    const code = generateOtpCode(5, () => 7);
    expect(code).toBe('77777');
  });

  it('only ever produces digits', () => {
    let n = 0;
    const code = generateOtpCode(8, () => n++ % 10);
    expect(code).toMatch(/^\d{8}$/);
  });
});
