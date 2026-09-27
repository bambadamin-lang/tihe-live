import { monotonicFactory } from 'ulid';
import { ID_PREFIXES, type IdKind } from '@tihe/contracts';

const ulid = monotonicFactory();

/** A prefixed ULID (`ses_01J8Z…`). Monotonic, so ids minted in one millisecond still sort. */
export function newId(kind: IdKind, now: number = Date.now()): string {
  return `${ID_PREFIXES[kind]}_${ulid(now)}`;
}

export type IdFactory = (kind: IdKind) => string;
