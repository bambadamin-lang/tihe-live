import { createHmac } from 'node:crypto';

import * as argon2 from 'argon2';

/**
 * Password hashing (ADR-0013).
 *
 * The password is first keyed with a server-side pepper (HMAC-SHA256), then hashed with
 * Argon2id. The pepper lives in the environment, not the database, so a stolen database alone
 * cannot be brute-forced; the HMAC also turns any password into a fixed-length input, so a very
 * long one costs Argon2 no more than a short one.
 */
export class PasswordHasher {
  private readonly pepper: Buffer;
  /** A real hash of nothing anyone knows, verified when the phone number is unknown. */
  private dummy: Promise<string> | undefined;

  constructor(pepperBase64: string) {
    this.pepper = Buffer.from(pepperBase64, 'base64');
    if (this.pepper.length < 16) throw new Error('PASSWORD_PEPPER must decode to 16+ bytes');
  }

  hash(password: string): Promise<string> {
    return argon2.hash(this.keyed(password), { type: argon2.argon2id });
  }

  async verify(hash: string, password: string): Promise<boolean> {
    try {
      return await argon2.verify(hash, this.keyed(password));
    } catch {
      // A malformed stored hash is a failed sign-in, never a 500 that tells the caller
      // something different happened for this account.
      return false;
    }
  }

  /**
   * Spends the same time as a real verification and always fails. Used when the phone number
   * has no account, so the response time does not reveal who studies at the institute.
   */
  async verifyAgainstNothing(password: string): Promise<false> {
    this.dummy ??= this.hash('tihe:no-such-account');
    await this.verify(await this.dummy, password);
    return false;
  }

  private keyed(password: string): string {
    return createHmac('sha256', this.pepper).update(password.normalize('NFC')).digest('base64');
  }
}

export type PasswordProblem = 'too_short' | 'too_long' | 'is_phone' | 'one_character';

/**
 * The policy for a new password: at least 8 characters, not the phone number, and not one
 * character repeated. Deliberately short — students set these on phones, and length beats
 * composition rules that push people towards `Password1!`.
 */
export function checkPasswordPolicy(password: string, phoneE164: string): PasswordProblem | null {
  const chars = [...password];
  if (chars.length < 8) return 'too_short';
  if (chars.length > 128) return 'too_long';
  if (new Set(chars).size === 1) return 'one_character';

  const digits = foldDigits(password).replace(/\D/g, '');
  const local = phoneE164.replace(/^\+98/, '0');
  const national = phoneE164.replace(/^\+98/, '');
  if (digits.length >= 10 && (local.includes(digits) || digits.includes(national))) {
    return 'is_phone';
  }
  return null;
}

function foldDigits(value: string): string {
  return value
    .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660));
}
