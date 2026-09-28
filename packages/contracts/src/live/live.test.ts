import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  BOARD_PALETTE,
  CAPABILITIES,
  DEFAULT_TOOL_WIDTH,
  PEN_STYLES,
  LAYOUT_PRESETS,
  POLICY_CAPABILITY,
  ROLE_PRESETS,
  ROLE_RANK,
  boardItemInputSchema,
  classroomCommandSchema,
  classroomEventSchema,
  classroomSnapshotSchema,
  clientMessageSchema,
  deriveRecordingLayout,
  joinResponseSchema,
  layoutProblems,
  layoutSchema,
  liveWatermarkText,
  serverMessageSchema,
  watermarkShortId,
  type Pod,
} from '../index.js';

/**
 * The fixtures in packages/contracts/fixtures/live are the cross-language contract: the Dart
 * client decodes the same files in its conformance tests. These tests make sure every fixture
 * is valid and that every command and event type has one, so Dart cannot silently miss a type.
 */
const fixture = (name: string): unknown =>
  JSON.parse(
    readFileSync(fileURLToPath(new URL(`../../fixtures/live/${name}`, import.meta.url)), 'utf8'),
  );

describe('fixtures', () => {
  it('snapshot is a valid classroom snapshot', () => {
    expect(classroomSnapshotSchema.parse(fixture('snapshot.json'))).toBeTruthy();
  });

  it('join response is valid', () => {
    expect(joinResponseSchema.parse(fixture('join-response.json'))).toBeTruthy();
  });

  it('every client message is valid, and every command type appears', () => {
    const messages = fixture('client-messages.json') as unknown[];
    const seen = new Set<string>();
    for (const raw of messages) {
      const msg = clientMessageSchema.parse(raw);
      if (msg.t === 'cmd') seen.add(msg.cmd.type);
    }
    const all = classroomCommandSchema.options.map((o) => o.shape.type.value);
    expect([...seen].sort()).toEqual([...all].sort());
  });

  it('every server message is valid, and every event type appears', () => {
    const messages = fixture('server-messages.json') as unknown[];
    const seen = new Set<string>();
    for (const raw of messages) {
      const msg = serverMessageSchema.parse(raw);
      if (msg.t === 'evt') seen.add(msg.evt.type);
    }
    const all = classroomEventSchema.options.map((o) => o.shape.type.value);
    expect([...seen].sort()).toEqual([...all].sort());
  });

  it('layout-presets.json matches LAYOUT_PRESETS exactly', () => {
    expect(fixture('layout-presets.json')).toEqual(LAYOUT_PRESETS);
  });

  it('board-styles.json matches the pen styles, widths and palette', () => {
    expect(fixture('board-styles.json')).toEqual({
      penStyles: PEN_STYLES,
      defaultWidths: DEFAULT_TOOL_WIDTH,
      palette: BOARD_PALETTE,
    });
  });

  it('watermark vectors match watermarkShortId', () => {
    const vectors = fixture('watermark-vectors.json') as { userId: string; shortId: string }[];
    expect(vectors.length).toBeGreaterThan(3);
    for (const v of vectors) expect(watermarkShortId(v.userId)).toBe(v.shortId);
  });
});

describe('roles', () => {
  it('ranks host > cohost > presenter > participant > recorder', () => {
    expect(ROLE_RANK.host).toBeGreaterThan(ROLE_RANK.cohost);
    expect(ROLE_RANK.cohost).toBeGreaterThan(ROLE_RANK.presenter);
    expect(ROLE_RANK.presenter).toBeGreaterThan(ROLE_RANK.participant);
    expect(ROLE_RANK.participant).toBeGreaterThan(ROLE_RANK.recorder);
  });

  it('gives the host every capability except raising a hand', () => {
    expect([...ROLE_PRESETS.host].sort()).toEqual(
      CAPABILITIES.filter((c) => c !== 'hand.raise').sort(),
    );
  });

  it('gives participants and the recorder nothing before policy', () => {
    expect(ROLE_PRESETS.participant).toEqual([]);
    expect(ROLE_PRESETS.recorder).toEqual([]);
  });

  it('never lets the room policy hand out management rights', () => {
    const fromPolicy = Object.values(POLICY_CAPABILITY);
    for (const cap of [
      'participants.manage',
      'roles.assign',
      'recording.control',
      'class.end',
      'whiteboard.manage',
      'layout.change',
    ] as const) {
      expect(fromPolicy).not.toContain(cap);
    }
  });
});

describe('layouts', () => {
  const p = (id: string, kind: Pod['kind'], x: number, y: number, w: number, h: number): Pod => ({
    id,
    kind,
    x,
    y,
    w,
    h,
  });

  it('every preset is valid and fills the whole grid', () => {
    for (const layout of Object.values(LAYOUT_PRESETS)) {
      expect(layoutProblems(layout.pods), layout.id).toEqual([]);
      const area = layout.pods.reduce((sum, pod) => sum + pod.w * pod.h, 0);
      expect(area, layout.id).toBe(144);
    }
  });

  it('rejects overlapping pods', () => {
    const problems = layoutProblems([p('a', 'speaker', 0, 0, 6, 6), p('b', 'chat', 5, 5, 4, 4)]);
    expect(problems).toContain('pods a and b overlap');
  });

  it('accepts pods that only touch at an edge', () => {
    expect(layoutProblems([p('a', 'speaker', 0, 0, 6, 12), p('b', 'chat', 6, 0, 6, 12)])).toEqual(
      [],
    );
  });

  it('rejects pods past the grid, duplicate kinds, duplicate ids, and empty layouts', () => {
    expect(layoutProblems([p('a', 'speaker', 8, 0, 6, 6)])).toContain(
      'pod a extends past the grid',
    );
    expect(layoutProblems([p('a', 'chat', 0, 0, 2, 2), p('b', 'chat', 4, 4, 2, 2)])).toContain(
      'more than one chat pod',
    );
    expect(layoutProblems([p('a', 'chat', 0, 0, 2, 2), p('a', 'hands', 4, 4, 2, 2)])).toContain(
      'duplicate pod id a',
    );
    expect(layoutProblems([])).toContain('a layout needs at least one pod');
  });

  it('layoutSchema refuses an invalid layout', () => {
    const bad = { id: 'custom', name: 'x', preset: null, pods: [p('a', 'speaker', 0, 0, 13, 1)] };
    expect(layoutSchema.safeParse(bad).success).toBe(false);
  });
});

describe('deriveRecordingLayout', () => {
  it('never records chat, participant or hand pods', () => {
    for (const layout of Object.values(LAYOUT_PRESETS)) {
      const rec = deriveRecordingLayout(layout);
      expect(layoutProblems(rec.pods), layout.id).toEqual([]);
      for (const pod of rec.pods) {
        expect(['chat', 'participants', 'hands'], layout.id).not.toContain(pod.kind);
      }
    }
  });

  it('gives the biggest content pod the main area', () => {
    const rec = deriveRecordingLayout(LAYOUT_PRESETS.presentation);
    expect(rec.pods[0]).toMatchObject({ kind: 'screen', x: 0, y: 0, w: 9, h: 12 });
    expect(rec.pods[1]).toMatchObject({ kind: 'speaker', x: 9, y: 0, w: 3, h: 4 });
  });

  it('breaks size ties screen-first', () => {
    const rec = deriveRecordingLayout(LAYOUT_PRESETS.split);
    expect(rec.pods.map((pod) => pod.kind)).toEqual(['screen', 'whiteboard', 'gallery', 'speaker']);
  });

  it('uses the full width when there is only one content pod', () => {
    const rec = deriveRecordingLayout(LAYOUT_PRESETS.lecture);
    expect(rec.pods).toEqual([{ id: 'speaker', kind: 'speaker', x: 0, y: 0, w: 12, h: 12 }]);
  });

  it('falls back to the speaker when a layout has no content pods', () => {
    const rec = deriveRecordingLayout({
      pods: [{ id: 'c', kind: 'chat', x: 0, y: 0, w: 12, h: 12 }],
    });
    expect(rec.pods).toEqual([{ id: 'speaker', kind: 'speaker', x: 0, y: 0, w: 12, h: 12 }]);
  });
});

describe('whiteboard items', () => {
  const stroke = {
    kind: 'stroke',
    id: 'wbi_01J8ZE00000000000000000001',
    pageId: 'wbp_01J8ZD00000000000000000001',
    color: '#1F4FD8',
    tool: 'pen',
    width: 30,
    points: [0, 0, 16000, 9000],
  };

  it('accepts points on the page edges', () => {
    expect(boardItemInputSchema.safeParse(stroke).success).toBe(true);
  });

  it('rejects points off the page', () => {
    expect(boardItemInputSchema.safeParse({ ...stroke, points: [0, 0, 16001, 10] }).success).toBe(
      false,
    );
    expect(boardItemInputSchema.safeParse({ ...stroke, points: [0, 9001] }).success).toBe(false);
  });

  it('rejects an odd number of coordinates', () => {
    expect(boardItemInputSchema.safeParse({ ...stroke, points: [1, 2, 3] }).success).toBe(false);
  });

  it('rejects strokes longer than 2000 points', () => {
    const points = Array.from({ length: 4002 }, (_, i) => i % 9000);
    expect(boardItemInputSchema.safeParse({ ...stroke, points }).success).toBe(false);
  });

  it('never stores eraser or laser strokes', () => {
    expect(boardItemInputSchema.safeParse({ ...stroke, tool: 'eraser' }).success).toBe(false);
    expect(boardItemInputSchema.safeParse({ ...stroke, tool: 'laser' }).success).toBe(false);
  });

  it('strips server-only fields a client tries to send', () => {
    const parsed = boardItemInputSchema.parse({ ...stroke, by: 'usr_01J8ZB00000000000000000001' });
    expect(parsed).not.toHaveProperty('by');
  });
});

describe('watermark', () => {
  it('is five ASCII digits', () => {
    expect(watermarkShortId('usr_01J8ZB00000000000000000001')).toMatch(/^\d{5}$/);
  });

  it('formats masked phone and short id', () => {
    const id = 'usr_01J8ZB00000000000000000001';
    expect(liveWatermarkText('0912•••6789', id)).toBe(`0912•••6789 · #${watermarkShortId(id)}`);
  });
});
