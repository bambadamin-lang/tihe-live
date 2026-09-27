import { describe, expect, it } from 'vitest';
import { ERROR_CODES, id, maskPhone, phoneSchema } from './common.js';
import { ERROR_CATALOG } from './errors.js';

describe('phoneSchema', () => {
  // Students type their number in every one of these forms. All must normalise to E.164,
  // because the phone number is the identity key for device binding and watermarking — two
  // spellings of one number would be two accounts.
  it.each([
    ['09123456789', '+989123456789'],
    ['+989123456789', '+989123456789'],
    ['00989123456789', '+989123456789'],
    ['989123456789', '+989123456789'],
    ['9123456789', '+989123456789'],
    ['0912 345 6789', '+989123456789'],
    ['0912-345-6789', '+989123456789'],
    ['۰۹۱۲۳۴۵۶۷۸۹', '+989123456789'], // Persian digits
    ['٠٩١٢٣٤٥٦٧٨٩', '+989123456789'], // Arabic-Indic digits
  ])('normalises %s', (input, expected) => {
    expect(phoneSchema.parse(input)).toBe(expected);
  });

  it.each([
    ['08123456789', 'wrong mobile prefix'],
    ['0912345678', 'too short'],
    ['091234567890', 'too long'],
    ['+15551234567', 'not an Iranian number'],
    ['', 'empty'],
    ['not a phone', 'not digits'],
  ])('rejects %s (%s)', (input) => {
    expect(() => phoneSchema.parse(input)).toThrow();
  });
});

describe('maskPhone', () => {
  it('shows only the first four and last four digits', () => {
    expect(maskPhone('+989123456789')).toBe('0912•••6789');
  });

  it('never leaks the middle digits', () => {
    const masked = maskPhone('+989123456789');
    expect(masked).not.toContain('345');
  });

  it('degrades safely on malformed input rather than echoing it', () => {
    expect(maskPhone('+9891')).not.toContain('91');
  });
});

describe('id', () => {
  it('accepts a correctly prefixed ULID', () => {
    expect(id('video').parse('vid_01J8ZQK5T9XVWR3M2N4P6H8B7C')).toBeTruthy();
  });

  it('rejects the right ULID under the wrong prefix', () => {
    // This is the bug the prefixes exist to catch: passing a course id where a video id goes.
    expect(() => id('video').parse('crs_01J8ZQK5T9XVWR3M2N4P6H8B7C')).toThrow();
  });

  it('rejects a bare ULID with no prefix', () => {
    expect(() => id('video').parse('01J8ZQK5T9XVWR3M2N4P6H8B7C')).toThrow();
  });

  it('rejects lowercase ULID bodies', () => {
    expect(() => id('video').parse('vid_01j8zqk5t9xvwr3m2n4p6h8b7c')).toThrow();
  });
});

describe('ERROR_CATALOG', () => {
  // A code with no Persian message would render as a blank error in the app. Since the client
  // relies on this catalog rather than its own mapping, a gap here is a user-visible bug.
  it('has an entry for every error code', () => {
    for (const code of ERROR_CODES) {
      expect(ERROR_CATALOG[code], `missing catalog entry for ${code}`).toBeDefined();
      expect(ERROR_CATALOG[code].messageFa.length).toBeGreaterThan(0);
    }
  });

  it('maps every code to a sane HTTP status', () => {
    for (const code of ERROR_CODES) {
      expect(ERROR_CATALOG[code].http).toBeGreaterThanOrEqual(400);
      expect(ERROR_CATALOG[code].http).toBeLessThan(600);
    }
  });
});
