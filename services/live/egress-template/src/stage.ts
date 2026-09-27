import { deriveRecordingLayout, type BoardPage, type Layout, type PodKind } from '@tihe/contracts';
import type { RoomState } from '../../src/core/room-state.js';
import { drawBoard, type Preview } from './board.js';

const EMPTY: Partial<Record<PodKind, string>> = {
  speaker: 'دوربین ارائه‌دهنده خاموش است',
  screen: 'اشتراک صفحه‌ای در جریان نیست',
  gallery: 'دوربینی روشن نیست',
};

/**
 * The recorded stage: the host's layout minus chat, participants and hands
 * (deriveRecordingLayout), on the same 12 × 12 grid in RTL, plus the institute mark. Pods for
 * video are filled by media.ts; the whiteboard pod is a canvas drawn here.
 */
export class Stage {
  private layoutKey = '';
  private readonly pods = new Map<PodKind, HTMLElement>();
  private canvas: HTMLCanvasElement | null = null;
  private readonly mark: HTMLElement;

  constructor(private readonly root: HTMLElement) {
    root.classList.add('stage');
    this.mark = document.createElement('div');
    this.mark.className = 'mark';
  }

  render(state: RoomState): void {
    const layout = deriveRecordingLayout(state.layout);
    const key = JSON.stringify(layout.pods);
    if (key !== this.layoutKey) this.mount(layout);
    this.layoutKey = key;
    this.renderMark(state.title, state.startedAt);
  }

  pod(kind: PodKind): HTMLElement | undefined {
    return this.pods.get(kind);
  }

  /** Shows the pod's "nothing here" placeholder, or hides it when content is present. */
  setEmpty(kind: PodKind, empty: boolean, label?: string): void {
    const pod = this.pods.get(kind);
    if (!pod) return;
    pod.classList.toggle('pod--empty', empty);
    const note = pod.querySelector<HTMLElement>('.pod__empty');
    if (note) note.textContent = label ?? EMPTY[kind] ?? '';
  }

  drawBoard(
    page: BoardPage | undefined,
    state: RoomState,
    previews: Iterable<Preview>,
    now: number,
  ): void {
    const canvas = this.canvas;
    if (!canvas || !page) return;
    const rect = canvas.getBoundingClientRect();
    const w = Math.round(rect.width * devicePixelRatio);
    const h = Math.round(rect.height * devicePixelRatio);
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }
    const ctx = canvas.getContext('2d');
    if (ctx) drawBoard(ctx, page, state.board.items.values(), previews, now);
  }

  private mount(layout: Layout): void {
    this.root.replaceChildren();
    this.pods.clear();
    this.canvas = null;
    for (const pod of layout.pods) {
      const el = document.createElement('section');
      el.className = `pod pod--${pod.kind}`;
      el.style.gridColumn = `${pod.x + 1} / span ${pod.w}`;
      el.style.gridRow = `${pod.y + 1} / span ${pod.h}`;
      const frame = document.createElement('div');
      frame.className = 'pod__frame';
      if (pod.kind === 'whiteboard') {
        // A whiteboard object — enamel in an aluminium frame with its marker tray — kept at
        // 16:9 inside whatever shape the pod has.
        const board = document.createElement('div');
        board.className = 'board';
        const body = document.createElement('div');
        body.className = 'board__body';
        this.canvas = document.createElement('canvas');
        const tray = document.createElement('div');
        tray.className = 'board__tray';
        body.append(this.canvas, tray);
        board.append(body);
        frame.append(board);
      } else {
        const media = document.createElement('div');
        media.className = 'pod__media';
        const empty = document.createElement('div');
        empty.className = 'pod__empty';
        empty.textContent = EMPTY[pod.kind] ?? '';
        frame.append(media, empty);
        el.classList.add('pod--empty');
      }
      el.append(frame);
      this.root.append(el);
      this.pods.set(pod.kind, el);
    }
    this.root.append(this.mark);
  }

  private renderMark(title: string, startedAt: string): void {
    const date = new Intl.DateTimeFormat('fa-IR-u-ca-persian', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    }).format(new Date(startedAt));
    this.mark.replaceChildren(
      Object.assign(document.createElement('strong'), { textContent: 'تیهه لایو' }),
      Object.assign(document.createElement('span'), { textContent: title }),
      Object.assign(document.createElement('span'), { textContent: date }),
    );
  }
}
