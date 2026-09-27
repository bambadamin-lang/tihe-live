import {
  CAPABILITIES,
  POLICY_CAPABILITY,
  ROLE_PRESETS,
  ROLE_RANK,
  type Capability,
  type ClassRole,
  type RoomPolicy,
} from '@tihe/contracts';

/**
 * The capability rules from docs/11-live-classroom.md §3. Everything that decides what someone
 * may do in class goes through this file, and every rule here has a test.
 */

/**
 * What a host can hand to an individual. Management rights are deliberately absent: they come
 * with a role (cohost, host), so "who can manage this class" is always answered by roles alone.
 */
export const GRANTABLE_CAPABILITIES: readonly Capability[] = [
  'publish.audio',
  'publish.video',
  'publish.screen',
  'whiteboard.draw',
  'whiteboard.manage',
  'chat.send',
  'hand.raise',
];

/** Granted when a raised hand is accepted, removed when the floor is taken back. */
export const FLOOR_CAPABILITIES: readonly Capability[] = ['publish.audio', 'publish.video'];

/**
 * effective = role preset ∪ policy (participants only) ∪ grants − revokes, in canonical order.
 * A host is never reduced: revokes do not apply to hosts, so a class can never be left
 * without someone able to run it.
 */
export function effectiveCapabilities(
  role: ClassRole,
  policy: RoomPolicy,
  grants: readonly Capability[],
  revokes: readonly Capability[],
): Capability[] {
  if (role === 'host') return [...ROLE_PRESETS.host];
  if (role === 'recorder') return [];

  const caps = new Set<Capability>(ROLE_PRESETS[role]);
  if (role === 'participant') {
    for (const [key, cap] of Object.entries(POLICY_CAPABILITY) as [
      keyof typeof POLICY_CAPABILITY,
      Capability,
    ][]) {
      if (policy[key]) caps.add(cap);
    }
  }
  for (const cap of grants) caps.add(cap);
  for (const cap of revokes) caps.delete(cap);
  return CAPABILITIES.filter((c) => caps.has(c));
}

/** Strictly higher rank. Two hosts cannot act on each other; the recorder is untouchable. */
export function outranks(actor: ClassRole, target: ClassRole): boolean {
  return target !== 'recorder' && ROLE_RANK[actor] > ROLE_RANK[target];
}

/** LiveKit track sources a set of capabilities allows. Names match LiveKit's TrackSource. */
export type MediaTrackSource = 'microphone' | 'camera' | 'screen_share' | 'screen_share_audio';
export type MediaKind = 'audio' | 'video' | 'screen';

export const MEDIA_CAPABILITY: Readonly<Record<MediaKind, Capability>> = {
  audio: 'publish.audio',
  video: 'publish.video',
  screen: 'publish.screen',
};

export function mediaSources(caps: readonly Capability[]): MediaTrackSource[] {
  const sources: MediaTrackSource[] = [];
  if (caps.includes('publish.audio')) sources.push('microphone');
  if (caps.includes('publish.video')) sources.push('camera');
  if (caps.includes('publish.screen')) sources.push('screen_share', 'screen_share_audio');
  return sources;
}

/** Media kinds present in `before` and missing in `after` — tracks the SFU must stop. */
export function lostMedia(
  before: readonly Capability[],
  after: readonly Capability[],
): MediaKind[] {
  return (Object.keys(MEDIA_CAPABILITY) as MediaKind[]).filter(
    (kind) => before.includes(MEDIA_CAPABILITY[kind]) && !after.includes(MEDIA_CAPABILITY[kind]),
  );
}

export function sameCapabilities(a: readonly Capability[], b: readonly Capability[]): boolean {
  return a.length === b.length && a.every((c, i) => c === b[i]);
}
