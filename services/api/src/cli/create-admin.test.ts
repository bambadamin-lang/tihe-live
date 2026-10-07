import { checkPasswordPolicy } from '@tihe/crypto';
import { describe, expect, it } from 'vitest';

import { generatePassword } from './create-admin.js';

describe('generatePassword', () => {
  it('is grouped in fours for dictation', () => {
    expect(generatePassword()).toMatch(/^[a-z2-9]{4}-[a-z2-9]{4}-[a-z2-9]{4}$/);
  });

  it('avoids characters that are confused when read aloud or typed', () => {
    const many = Array.from({ length: 200 }, () => generatePassword()).join('');
    expect(many).not.toMatch(/[01ilo]/);
  });

  it('always passes the password policy', () => {
    for (let i = 0; i < 200; i++) {
      expect(checkPasswordPolicy(generatePassword(), '+989123456789')).toBeNull();
    }
  });

  it('does not repeat', () => {
    const seen = new Set(Array.from({ length: 500 }, () => generatePassword()));
    expect(seen.size).toBe(500);
  });
});
