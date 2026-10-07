import { randomBytes } from 'node:crypto';

import * as argon2 from 'argon2';
import { describe, expect, it } from 'vitest';

import { checkPasswordPolicy, PasswordHasher } from './password.js';

const pepper = randomBytes(32).toString('base64');

describe('PasswordHasher', () => {
  const hasher = new PasswordHasher(pepper);

  it('verifies the right password and refuses a wrong one', async () => {
    const hash = await hasher.hash('سلام-دنیا-۱۴۰۵');
    expect(await hasher.verify(hash, 'سلام-دنیا-۱۴۰۵')).toBe(true);
    expect(await hasher.verify(hash, 'سلام-دنیا-۱۴۰۶')).toBe(false);
  });

  it('stores Argon2id, never the password', async () => {
    const hash = await hasher.hash('correct horse battery');
    expect(hash.startsWith('$argon2id$')).toBe(true);
    expect(hash).not.toContain('correct horse battery');
  });

  it('salts: the same password hashes differently each time', async () => {
    expect(await hasher.hash('same password')).not.toBe(await hasher.hash('same password'));
  });

  it('depends on the pepper: a hash is useless with another pepper', async () => {
    const hash = await hasher.hash('peppered password');
    const other = new PasswordHasher(randomBytes(32).toString('base64'));
    expect(await other.verify(hash, 'peppered password')).toBe(false);
  });

  it('cannot be checked by plain Argon2 without the pepper (a database dump alone)', async () => {
    const hash = await hasher.hash('dump me');
    expect(await argon2.verify(hash, 'dump me')).toBe(false);
  });

  it('treats a composed and a decomposed spelling as the same password', async () => {
    // "é" typed as one code point on one keyboard and as e + combining accent on another.
    const hash = await hasher.hash('café-latte');
    expect(await hasher.verify(hash, 'café-latte')).toBe(true);
  });

  it('fails, not throws, on a malformed stored hash', async () => {
    expect(await hasher.verify('not-a-hash', 'anything')).toBe(false);
  });

  it('verifyAgainstNothing always fails', async () => {
    expect(await hasher.verifyAgainstNothing('tihe:no-such-account')).toBe(false);
  });

  it('refuses a short pepper at construction', () => {
    expect(() => new PasswordHasher(Buffer.from('short').toString('base64'))).toThrow();
  });
});

describe('checkPasswordPolicy', () => {
  const phone = '+989123456789';

  it('accepts an ordinary passphrase', () => {
    expect(checkPasswordPolicy('کلاس ریاضی ۹۸', phone)).toBeNull();
    expect(checkPasswordPolicy('tihe-2026-autumn', phone)).toBeNull();
  });

  it('needs at least 8 characters, counted as characters not bytes', () => {
    expect(checkPasswordPolicy('1234567', phone)).toBe('too_short');
    // Seven Persian letters are 14 UTF-8 bytes but still seven characters.
    expect(checkPasswordPolicy('سلامسلا', phone)).toBe('too_short');
    expect(checkPasswordPolicy('12345678', phone)).toBeNull();
  });

  it('refuses one repeated character', () => {
    expect(checkPasswordPolicy('aaaaaaaaaa', phone)).toBe('one_character');
  });

  it('refuses the phone number in any of the forms students type it', () => {
    expect(checkPasswordPolicy('09123456789', phone)).toBe('is_phone');
    expect(checkPasswordPolicy('9123456789', phone)).toBe('is_phone');
    expect(checkPasswordPolicy('۰۹۱۲۳۴۵۶۷۸۹', phone)).toBe('is_phone');
    expect(checkPasswordPolicy('+989123456789', phone)).toBe('is_phone');
    expect(checkPasswordPolicy('0912-345-6789', phone)).toBe('is_phone');
  });

  it('does not refuse another number that happens to share digits', () => {
    expect(checkPasswordPolicy('09350000000', phone)).toBeNull();
  });

  it('caps the length', () => {
    expect(checkPasswordPolicy('x'.repeat(64) + 'y'.repeat(65), phone)).toBe('too_long');
  });
});
