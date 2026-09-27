/**
 * OTP rate-limiting and verification policy, as pure functions.
 *
 * Kept free of Nest and Prisma so it can be tested exhaustively — this is the code that stands
 * between the institute and both an SMS bill and an account takeover, and it is exactly the kind
 * of logic that fails silently when it is only reachable through an HTTP request.
 */

export interface OtpAttemptRecord {
  createdAt: Date;
  consumedAt: Date | null;
}

export interface OtpPolicyConfig {
  ttlSeconds: number;
  resendAfterSeconds: number;
  maxPerPhonePerHour: number;
  maxPerIpPerHour: number;
  maxAttempts: number;
}

export type OtpRequestDecision =
  | { allowed: true }
  | { allowed: false; reason: 'resend_too_soon'; retryAfterSeconds: number }
  | { allowed: false; reason: 'phone_hourly_limit' }
  | { allowed: false; reason: 'ip_hourly_limit' };

/**
 * Decides whether a new code may be sent.
 *
 * Three independent limits, because they stop different things:
 *   * resend cooldown — stops the "didn't arrive, tap again" loop costing five messages
 *   * per-phone hourly — stops one number being used to burn credit
 *   * per-IP hourly — stops one script enumerating many numbers, which the cooldown does not
 */
export function decideOtpRequest(
  now: Date,
  config: OtpPolicyConfig,
  recentForPhone: OtpAttemptRecord[],
  recentForIpCount: number,
): OtpRequestDecision {
  const hourAgo = new Date(now.getTime() - 3_600_000);

  const lastForPhone = recentForPhone
    .filter((r) => r.createdAt > hourAgo)
    .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())[0];

  if (lastForPhone) {
    const elapsed = (now.getTime() - lastForPhone.createdAt.getTime()) / 1000;
    if (elapsed < config.resendAfterSeconds) {
      return {
        allowed: false,
        reason: 'resend_too_soon',
        retryAfterSeconds: Math.ceil(config.resendAfterSeconds - elapsed),
      };
    }
  }

  const phoneCount = recentForPhone.filter((r) => r.createdAt > hourAgo).length;
  if (phoneCount >= config.maxPerPhonePerHour) {
    return { allowed: false, reason: 'phone_hourly_limit' };
  }

  if (recentForIpCount >= config.maxPerIpPerHour) {
    return { allowed: false, reason: 'ip_hourly_limit' };
  }

  return { allowed: true };
}

export type OtpVerifyOutcome = 'ok' | 'expired' | 'consumed' | 'too_many_attempts' | 'mismatch';

export interface OtpVerifyState {
  expiresAt: Date;
  consumedAt: Date | null;
  attemptCount: number;
}

/**
 * Checks everything about a code except whether it matches, which requires a hash comparison the
 * caller performs.
 *
 * Order matters: attempt count is checked before the hash comparison, so an attacker cannot use
 * timing to distinguish "wrong code" from "locked out", and a locked record stops costing CPU.
 */
export function checkOtpState(
  now: Date,
  config: OtpPolicyConfig,
  state: OtpVerifyState,
): Exclude<OtpVerifyOutcome, 'mismatch'> | 'check_hash' {
  if (state.consumedAt !== null) return 'consumed';
  if (state.attemptCount >= config.maxAttempts) return 'too_many_attempts';
  if (now > state.expiresAt) return 'expired';
  return 'check_hash';
}

/**
 * Generates a numeric code of the configured length.
 *
 * `randomInt` rather than `Math.random`: a predictable OTP is the same as no OTP, and
 * `Math.random` is seeded predictably enough to matter.
 */
export function generateOtpCode(length: number, randomInt: (max: number) => number): string {
  let code = '';
  for (let i = 0; i < length; i += 1) {
    code += String(randomInt(10));
  }
  return code;
}
