import { LAYOUT_PRESETS, classroomSnapshotSchema, layoutPresetKeySchema } from '@tihe/contracts';
import snapshot from '../../../../packages/contracts/fixtures/live/snapshot.json';
import { roomStateFromSnapshot } from '../../src/core/room-state.js';
import type { Preview } from './board.js';
import { Stage } from './stage.js';

/**
 * `?demo[&layout=split]`: the recording of the fixture classroom, with painted placeholders
 * instead of video. Used by `pnpm screenshot` to check the recorded stage without LiveKit.
 */
export function runDemo(root: HTMLElement, params: URLSearchParams): void {
  const state = roomStateFromSnapshot(classroomSnapshotSchema.parse(snapshot), 0);
  const layoutKey = layoutPresetKeySchema.safeParse(params.get('layout'));
  if (layoutKey.success) state.layout = LAYOUT_PRESETS[layoutKey.data];

  const stage = new Stage(root);
  stage.render(state);

  const placeholder = (label: string, hue: number) => {
    const el = document.createElement('div');
    el.className = 'demo-video';
    el.style.background = `radial-gradient(circle at 50% 35%, hsl(${hue} 30% 62%), hsl(${hue} 28% 22%))`;
    el.textContent = label;
    return el;
  };
  const fill = (kind: 'speaker' | 'screen' | 'gallery', els: HTMLElement[]) => {
    const box = stage.pod(kind)?.querySelector<HTMLElement>('.pod__media');
    if (!box) return;
    box.replaceChildren(...els);
    box.dataset.count = String(els.length);
    stage.setEmpty(kind, els.length === 0);
  };
  fill('speaker', [placeholder('دکتر رضایی', 28)]);
  fill('screen', [placeholder('اسلاید: مشتق توابع مرکب', 210)]);
  fill(
    'gallery',
    ['دکتر رضایی', 'مریم احمدی', 'سارا محمدی'].map((n, i) => placeholder(n, 28 + i * 70)),
  );

  const laser: Preview = {
    tool: 'laser',
    color: '#D32F2F',
    width: 60,
    points: [11200, 6200, 11500, 6300, 11800, 6250, 12100, 6400],
    updatedAt: Date.now(),
  };
  const draw = () => {
    const page = state.board.pages.find((p) => p.id === state.board.activePageId);
    stage.drawBoard(page, state, [laser], laser.updatedAt);
    document.body.dataset.ready = 'true';
  };
  document.fonts.ready.then(draw);
}
