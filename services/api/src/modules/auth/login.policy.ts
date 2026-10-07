/**
 * Sign-in rate limiting (ADR-0013), as a pure function over the failures in the window, so the
 * time arithmetic is tested without a database or a clock.
 *
 * Failures are counted per phone number (guessing one student's password) and per address (one
 * machine trying many students). Successful sign-ins do not count, so a student who mistypes a
 * few times and then gets it right is never locked out by their own success.
 */
export interface LoginPolicy {
  windowMinutes: number;
  maxFailuresPerPhone: number;
  maxFailuresPerIp: number;
}

export type LoginDecision = { allowed: true } | { allowed: false; retryAfterSeconds: number };

export function decideLoginAttempt(
  now: Date,
  policy: LoginPolicy,
  phoneFailures: readonly Date[],
  ipFailures: readonly Date[],
): LoginDecision {
  const windowMs = policy.windowMinutes * 60_000;
  const since = now.getTime() - windowMs;

  const waitFor = (failures: readonly Date[], max: number): number => {
    const recent = failures
      .map((d) => d.getTime())
      .filter((t) => t > since)
      .sort((a, b) => a - b);
    if (recent.length < max) return 0;
    // Allowed again once enough of the oldest failures have left the window that fewer than
    // `max` remain.
    const leaving = recent[recent.length - max];
    return leaving === undefined ? 0 : leaving + windowMs - now.getTime();
  };

  const waitMs = Math.max(
    waitFor(phoneFailures, policy.maxFailuresPerPhone),
    waitFor(ipFailures, policy.maxFailuresPerIp),
  );
  if (waitMs <= 0) return { allowed: true };
  return { allowed: false, retryAfterSeconds: Math.ceil(waitMs / 1000) };
}
