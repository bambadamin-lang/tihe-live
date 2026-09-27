import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { serverMessageSchema, type ServerMessage } from '@tihe/contracts';
import { describe, expect, it } from 'vitest';
import { strokeOutline, textDirectionOf } from './board.js';
import { ClassroomFeed } from './feed.js';

const messages = (
  JSON.parse(
    readFileSync(
      fileURLToPath(
        new URL(
          '../../../../packages/contracts/fixtures/live/server-messages.json',
          import.meta.url,
        ),
      ),
      'utf8',
    ),
  ) as unknown[]
).map((m) => serverMessageSchema.parse(m));
const welcome = messages.find((m) => m.t === 'welcome' && m.snapshot)!;

const feedWith = () => {
  const changes: string[] = [];
  const feed = new ClassroomFeed('ws://unused', 'ticket', (what) => changes.push(what));
  feed.receive(welcome);
  return { feed, changes };
};

describe('ClassroomFeed', () => {
  it('builds the room from the welcome snapshot', () => {
    const { feed, changes } = feedWith();
    expect(feed.state?.layout.id).toBe('whiteboard');
    expect(feed.state?.board.items.size).toBe(5);
    expect(changes).toEqual(['state']);
  });

  it('ignores events it has already applied', () => {
    const { feed } = feedWith();
    const stale: ServerMessage = {
      t: 'evt',
      seq: 1,
      at: '2026-09-27T06:30:00.000Z',
      evt: { type: 'wb.cleared', pageId: feed.state!.board.activePageId },
    };
    feed.receive(stale);
    expect(feed.state?.board.items.size).toBe(5);
  });

  it('accumulates previews and drops one when its item is committed', () => {
    const { feed } = feedWith();
    const base = { t: 'eph', from: 'usr_01J8ZB00000000000000000001' } as const;
    const eph = {
      type: 'wb.progress',
      strokeId: 'wbi_01J8ZE0000000000000000000A',
      pageId: feed.state!.board.activePageId,
      tool: 'pen',
      color: '#1B1B1F',
      width: 30,
      done: false,
    } as const;
    feed.receive({ ...base, eph: { ...eph, points: [1, 1, 2, 2] } });
    feed.receive({ ...base, eph: { ...eph, points: [3, 3], done: true } });
    expect(feed.previews.get(eph.strokeId)?.points).toEqual([1, 1, 2, 2, 3, 3]);

    const committed = messages.find((m) => m.t === 'evt' && m.evt.type === 'wb.added')!;
    if (committed.t !== 'evt' || committed.evt.type !== 'wb.added') throw new Error('fixture');
    feed.receive({
      ...committed,
      seq: feed.state!.seq + 1,
      evt: { ...committed.evt, items: [{ ...committed.evt.items[0]!, id: eph.strokeId }] },
    });
    expect(feed.previews.has(eph.strokeId)).toBe(false);
  });

  it('forgets previews whose author went quiet', () => {
    const { feed } = feedWith();
    feed.previews.set('x', {
      tool: 'laser',
      color: '#D32F2F',
      width: 60,
      points: [0, 0],
      updatedAt: 0,
    });
    expect(feed.sweep(10_000)).toBe(true);
    expect(feed.previews.size).toBe(0);
  });

  it('reports the end of class so the recording stops', () => {
    const { feed, changes } = feedWith();
    feed.receive({
      t: 'evt',
      seq: feed.state!.seq + 1,
      at: '2026-09-27T08:00:00.000Z',
      evt: { type: 'class.ended', reason: 'host_ended' },
    });
    expect(changes.at(-1)).toBe('ended');
  });
});

describe('strokeOutline', () => {
  it('produces a closed outline around the stroke', () => {
    const outline = strokeOutline([0, 0, 1000, 0, 2000, 500], 60, 'marker');
    expect(outline.length).toBeGreaterThan(8);
    const ys = outline.map((p) => p[1]!);
    expect(Math.min(...ys)).toBeLessThan(0);
    expect(Math.max(...ys)).toBeGreaterThan(500);
  });
});

describe('textDirectionOf', () => {
  it('reads Persian right to left and a formula left to right', () => {
    expect(textDirectionOf('مشتق توابع مرکب')).toBe('rtl');
    expect(textDirectionOf('(f(g(x)))′ = f′(g(x))')).toBe('ltr');
    expect(textDirectionOf('مثال: y = sin(x²)')).toBe('rtl');
    expect(textDirectionOf('= 42')).toBe('rtl');
  });
});
