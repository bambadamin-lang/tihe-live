import { describe, expect, it } from 'vitest';

import { decideLoginAttempt, type LoginPolicy } from './login.policy.js';

const policy: LoginPolicy = { windowMinutes: 15, maxFailuresPerPhone: 3, maxFailuresPerIp: 5 };
const now = new Date('2026-10-04T10:00:00Z');
const ago = (seconds: number) => new Date(now.getTime() - seconds * 1000);

describe('decideLoginAttempt', () => {
  it('allows a first attempt', () => {
    expect(decideLoginAttempt(now, policy, [], [])).toEqual({ allowed: true });
  });

  it('allows up to the limit and refuses at it', () => {
    expect(decideLoginAttempt(now, policy, [ago(30), ago(20)], [])).toEqual({ allowed: true });
    const decision = decideLoginAttempt(now, policy, [ago(30), ago(20), ago(10)], []);
    expect(decision.allowed).toBe(false);
  });

  it('waits until the oldest failure leaves the window', () => {
    // Window 900 s; the oldest failure was 30 s ago, so it leaves in 870 s.
    const decision = decideLoginAttempt(now, policy, [ago(30), ago(20), ago(10)], []);
    expect(decision).toEqual({ allowed: false, retryAfterSeconds: 870 });
  });

  it('waits for enough failures to leave when there are more than the limit', () => {
    // Five failures, limit 3: three must leave so that two remain; the third oldest (300 s ago)
    // leaves in 600 s.
    const failures = [ago(500), ago(400), ago(300), ago(200), ago(100)];
    expect(decideLoginAttempt(now, policy, failures, [])).toEqual({
      allowed: false,
      retryAfterSeconds: 600,
    });
  });

  it('ignores failures older than the window', () => {
    const failures = [ago(901), ago(1000), ago(5000), ago(20)];
    expect(decideLoginAttempt(now, policy, failures, [])).toEqual({ allowed: true });
  });

  it('allows again exactly when the window passes', () => {
    const failures = [ago(900), ago(899), ago(898)];
    // The first is now outside (window is strictly the last 900 s), so two remain.
    expect(decideLoginAttempt(now, policy, failures, [])).toEqual({ allowed: true });
  });

  it('limits one address trying many numbers', () => {
    const ip = [ago(50), ago(40), ago(30), ago(20), ago(10)];
    expect(decideLoginAttempt(now, policy, [], ip)).toEqual({
      allowed: false,
      retryAfterSeconds: 850,
    });
  });

  it('takes the longer wait when both limits are hit', () => {
    const phone = [ago(100), ago(90), ago(80)]; // free in 800 s
    const ip = [ago(10), ago(9), ago(8), ago(7), ago(6)]; // free in 890 s
    expect(decideLoginAttempt(now, policy, phone, ip)).toEqual({
      allowed: false,
      retryAfterSeconds: 890,
    });
  });

  it('does not depend on the order failures are given in', () => {
    const sorted = [ago(30), ago(20), ago(10)];
    const shuffled = [ago(20), ago(10), ago(30)];
    expect(decideLoginAttempt(now, policy, shuffled, [])).toEqual(
      decideLoginAttempt(now, policy, sorted, []),
    );
  });
});
