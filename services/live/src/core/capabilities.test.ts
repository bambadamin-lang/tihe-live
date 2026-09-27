import { DEFAULT_ROOM_POLICY, ROLE_PRESETS } from '@tihe/contracts';
import { describe, expect, it } from 'vitest';
import { effectiveCapabilities, lostMedia, mediaSources, outranks } from './capabilities.js';

const policy = DEFAULT_ROOM_POLICY;

describe('effectiveCapabilities', () => {
  it('gives a participant under the default policy only chat and hand-raising', () => {
    expect(effectiveCapabilities('participant', policy, [], [])).toEqual([
      'chat.send',
      'hand.raise',
    ]);
  });

  it('applies each policy toggle to participants', () => {
    const open = {
      ...policy,
      participantsCanUnmute: true,
      participantsCanStartVideo: true,
      participantsCanShareScreen: true,
      participantsCanDraw: true,
      participantsCanChat: false,
      handRaiseEnabled: false,
    };
    expect(effectiveCapabilities('participant', open, [], [])).toEqual([
      'publish.audio',
      'publish.video',
      'publish.screen',
      'whiteboard.draw',
    ]);
  });

  it('does not apply the participant policy to other roles', () => {
    const closed = { ...policy, participantsCanChat: false, handRaiseEnabled: false };
    expect(effectiveCapabilities('presenter', closed, [], [])).toEqual([...ROLE_PRESETS.presenter]);
  });

  it('adds grants and removes revokes, revokes winning', () => {
    expect(
      effectiveCapabilities('participant', policy, ['whiteboard.draw'], ['chat.send']),
    ).toEqual(['whiteboard.draw', 'hand.raise']);
    expect(
      effectiveCapabilities('participant', policy, ['publish.audio'], ['publish.audio']),
    ).not.toContain('publish.audio');
  });

  it('never reduces a host', () => {
    expect(effectiveCapabilities('host', policy, [], ['class.end', 'participants.manage'])).toEqual(
      [...ROLE_PRESETS.host],
    );
  });

  it('gives the recorder nothing, whatever it is granted', () => {
    expect(effectiveCapabilities('recorder', policy, ['publish.audio'], [])).toEqual([]);
  });
});

describe('outranks', () => {
  it('orders host > cohost > presenter > participant', () => {
    expect(outranks('host', 'cohost')).toBe(true);
    expect(outranks('cohost', 'presenter')).toBe(true);
    expect(outranks('presenter', 'participant')).toBe(true);
  });

  it('refuses equal rank and upward action', () => {
    expect(outranks('host', 'host')).toBe(false);
    expect(outranks('cohost', 'cohost')).toBe(false);
    expect(outranks('cohost', 'host')).toBe(false);
  });

  it('makes the recorder untouchable', () => {
    expect(outranks('host', 'recorder')).toBe(false);
  });
});

describe('media mapping', () => {
  it('maps capabilities to LiveKit sources, screen share with its audio', () => {
    expect(mediaSources(['publish.audio', 'publish.screen'])).toEqual([
      'microphone',
      'screen_share',
      'screen_share_audio',
    ]);
    expect(mediaSources(['chat.send'])).toEqual([]);
  });

  it('reports only media that was lost', () => {
    expect(lostMedia(['publish.audio', 'publish.video'], ['publish.video'])).toEqual(['audio']);
    expect(lostMedia(['chat.send'], ['publish.audio'])).toEqual([]);
  });
});
