import { ID_PREFIXES, type IdKind } from '@tihe/contracts';
import { ulid } from 'ulid';

export { ID_PREFIXES, type IdKind };

/**
 * Generates a prefixed ULID.
 *
 * ULIDs sort by creation time, which makes cursor pagination trivial, and the prefix makes a
 * mis-passed id obvious in a log line — worth it when four id types flow through one playback
 * request.
 *
 * Lives here rather than in the API because every writer of rows needs it: the API, `media-worker`
 * (asset and content-key ids) and `ingest-worker` (recording ids).
 */
export function newId(kind: IdKind): string {
  return `${ID_PREFIXES[kind]}_${ulid()}`;
}

export function isId(kind: IdKind, value: string): boolean {
  return value.startsWith(`${ID_PREFIXES[kind]}_`);
}
