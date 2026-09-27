import { describe, expect, it } from 'vitest';

import { normalizeFa, prepareSearchQuery } from './search.js';

describe('normalizeFa', () => {
  it('folds Arabic kaf to Persian keheh', () => {
    // A student typing on an Arabic keyboard must still find Persian-typed titles.
    expect(normalizeFa('كتاب')).toBe(normalizeFa('کتاب'));
  });

  it('folds Arabic yeh variants to Persian yeh', () => {
    expect(normalizeFa('عربي')).toBe(normalizeFa('عربی'));
    expect(normalizeFa('حتى')).toBe(normalizeFa('حتی'));
  });

  it('folds alef variants', () => {
    expect(normalizeFa('آب')).toBe(normalizeFa('اب'));
    expect(normalizeFa('أحمد')).toBe(normalizeFa('احمد'));
  });

  it('strips the zero-width non-joiner', () => {
    // می‌شود and میشود are the same word; only one of them is usually typed.
    expect(normalizeFa('می‌شود')).toBe(normalizeFa('میشود'));
  });

  it('strips diacritics', () => {
    expect(normalizeFa('مُشتَق')).toBe(normalizeFa('مشتق'));
  });

  it('strips tatweel', () => {
    expect(normalizeFa('ریاضـــیات')).toBe(normalizeFa('ریاضیات'));
  });

  it('converts Persian digits to Western', () => {
    expect(normalizeFa('نیمسال ۱۴۰۵')).toBe('نیمسال 1405');
  });

  it('converts Arabic-Indic digits to Western', () => {
    expect(normalizeFa('جلسه ٤')).toBe('جلسه 4');
  });

  it('collapses whitespace', () => {
    expect(normalizeFa('  جلسه    چهارم  ')).toBe('جلسه چهارم');
  });

  it('lowercases Latin text so mixed titles match', () => {
    expect(normalizeFa('Calculus مشتق')).toBe('calculus مشتق');
  });

  it('is idempotent', () => {
    // The generated column applies this once; a query applies it again. Both must land in the
    // same place or nothing ever matches.
    const once = normalizeFa('كتاب مُشتَق ۱۴۰۵ می‌شود');
    expect(normalizeFa(once)).toBe(once);
  });

  it('leaves already-normal text unchanged', () => {
    expect(normalizeFa('مشتق توابع مرکب')).toBe('مشتق توابع مرکب');
  });
});

describe('prepareSearchQuery', () => {
  it('normalises and caps length', () => {
    expect(prepareSearchQuery('  كتاب  ')).toBe('کتاب');
    expect(prepareSearchQuery('x'.repeat(500))).toHaveLength(120);
  });
});
