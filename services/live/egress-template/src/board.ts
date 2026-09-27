import {
  BOARD_HEIGHT,
  BOARD_WIDTH,
  PEN_STYLES,
  type BoardItem,
  type BoardPage,
  type PenTool,
} from '@tihe/contracts';
import { getStroke } from 'perfect-freehand';

/**
 * Draws one whiteboard page onto a canvas, in page units scaled to the canvas. Mirrors the
 * Flutter painter in tihe_classroom: same perfect-freehand settings (PEN_STYLES), same paint
 * order, same backgrounds — the recording must look like the live board.
 */

/** An in-progress stroke or laser trail from wb.progress messages. */
export interface Preview {
  tool: PenTool | 'laser';
  color: string;
  width: number;
  points: number[];
  updatedAt: number;
}

export const LASER_FADE_MS = 1200;
export const FONT_STACK = 'Peyda, Vazirmatn, "Noto Sans Arabic", Tahoma, sans-serif';

const pairs = (flat: readonly number[]): [number, number][] => {
  const out: [number, number][] = [];
  for (let i = 0; i + 1 < flat.length; i += 2) out.push([flat[i]!, flat[i + 1]!]);
  return out;
};

/** The filled outline of a pen stroke — the polygon perfect-freehand produces. */
export function strokeOutline(points: readonly number[], width: number, tool: PenTool): number[][] {
  const style = PEN_STYLES[tool];
  return getStroke(pairs(points), {
    size: width,
    thinning: style.thinning,
    smoothing: style.smoothing,
    streamline: style.streamline,
    simulatePressure: style.simulatePressure,
    last: true,
  });
}

function outlinePath(outline: number[][]): Path2D {
  const path = new Path2D();
  if (outline.length === 0) return path;
  const [first, ...rest] = outline;
  path.moveTo(first![0]!, first![1]!);
  // Quadratic curves through midpoints: the smoothing perfect-freehand's own SVG helper uses.
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i]!;
    const b = rest[(i + 1) % rest.length]!;
    path.quadraticCurveTo(a[0]!, a[1]!, (a[0]! + b[0]!) / 2, (a[1]! + b[1]!) / 2);
  }
  path.closePath();
  return path;
}

function drawBackground(ctx: CanvasRenderingContext2D, page: BoardPage): void {
  ctx.fillStyle = '#FBFBF7';
  ctx.fillRect(0, 0, BOARD_WIDTH, BOARD_HEIGHT);
  ctx.strokeStyle = 'rgba(80, 110, 160, 0.16)';
  ctx.fillStyle = 'rgba(80, 110, 160, 0.28)';
  ctx.lineWidth = 8;
  if (page.background === 'grid') {
    for (let x = 500; x < BOARD_WIDTH; x += 500) line(ctx, x, 0, x, BOARD_HEIGHT);
    for (let y = 500; y < BOARD_HEIGHT; y += 500) line(ctx, 0, y, BOARD_WIDTH, y);
  } else if (page.background === 'lines') {
    for (let y = 600; y < BOARD_HEIGHT; y += 450) line(ctx, 0, y, BOARD_WIDTH, y);
  } else if (page.background === 'dots') {
    for (let x = 500; x < BOARD_WIDTH; x += 500) {
      for (let y = 500; y < BOARD_HEIGHT; y += 500) ctx.fillRect(x - 12, y - 12, 24, 24);
    }
  }
}

function line(ctx: CanvasRenderingContext2D, x1: number, y1: number, x2: number, y2: number) {
  ctx.beginPath();
  ctx.moveTo(x1, y1);
  ctx.lineTo(x2, y2);
  ctx.stroke();
}

function drawPen(
  ctx: CanvasRenderingContext2D,
  tool: PenTool,
  color: string,
  width: number,
  points: readonly number[],
) {
  const style = PEN_STYLES[tool];
  ctx.save();
  ctx.globalAlpha = style.opacity;
  if (style.underlay) ctx.globalCompositeOperation = 'multiply';
  ctx.fillStyle = color;
  if (points.length === 2) {
    // A tap: a dot the width of the pen.
    ctx.beginPath();
    ctx.arc(points[0]!, points[1]!, width / 2, 0, Math.PI * 2);
    ctx.fill();
  } else {
    ctx.fill(outlinePath(strokeOutline(points, width, tool)));
  }
  ctx.restore();
}

function drawItem(ctx: CanvasRenderingContext2D, item: BoardItem): void {
  switch (item.kind) {
    case 'stroke':
      return drawPen(ctx, item.tool, item.color, item.width, item.points);
    case 'shape': {
      const [x1, y1] = item.from;
      const [x2, y2] = item.to;
      ctx.save();
      ctx.strokeStyle = item.color;
      ctx.lineWidth = item.width;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.beginPath();
      if (item.shape === 'rect') {
        ctx.rect(Math.min(x1, x2), Math.min(y1, y2), Math.abs(x2 - x1), Math.abs(y2 - y1));
      } else if (item.shape === 'ellipse') {
        ctx.ellipse(
          (x1 + x2) / 2,
          (y1 + y2) / 2,
          Math.abs(x2 - x1) / 2,
          Math.abs(y2 - y1) / 2,
          0,
          0,
          Math.PI * 2,
        );
      } else {
        ctx.moveTo(x1, y1);
        ctx.lineTo(x2, y2);
      }
      if (item.fill && (item.shape === 'rect' || item.shape === 'ellipse')) {
        ctx.fillStyle = item.fill;
        ctx.fill();
      }
      ctx.stroke();
      if (item.shape === 'arrow') {
        const angle = Math.atan2(y2 - y1, x2 - x1);
        const head = Math.max(item.width * 4, 180);
        ctx.beginPath();
        ctx.moveTo(x2, y2);
        ctx.lineTo(x2 - head * Math.cos(angle - 0.5), y2 - head * Math.sin(angle - 0.5));
        ctx.moveTo(x2, y2);
        ctx.lineTo(x2 - head * Math.cos(angle + 0.5), y2 - head * Math.sin(angle + 0.5));
        ctx.stroke();
      }
      ctx.restore();
      return;
    }
    case 'text': {
      ctx.save();
      ctx.fillStyle = item.color;
      ctx.font = `${item.size}px ${FONT_STACK}`;
      // Its own direction (a formula reads left to right), right-aligned at `at` — the same
      // rule as the Flutter painter's textDirectionOf.
      ctx.direction = textDirectionOf(item.text);
      ctx.textAlign = 'right';
      ctx.textBaseline = 'top';
      item.text
        .split('\n')
        .forEach((text, i) => ctx.fillText(text, item.at[0], item.at[1] + i * item.size * 1.4));
      ctx.restore();
      return;
    }
  }
}

const RTL_CHAR = /[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/;
const LTR_CHAR = /[A-Za-z\u00C0-\u024F]/;

/** The direction of a piece of text from its first strong character (RTL when there is none). */
export function textDirectionOf(text: string): 'rtl' | 'ltr' {
  for (const ch of text) {
    if (RTL_CHAR.test(ch)) return 'rtl';
    if (LTR_CHAR.test(ch)) return 'ltr';
  }
  return 'rtl';
}

function drawLaser(ctx: CanvasRenderingContext2D, preview: Preview, now: number): void {
  const fade = 1 - Math.min(1, (now - preview.updatedAt) / LASER_FADE_MS);
  if (fade <= 0) return;
  const pts = pairs(preview.points);
  ctx.save();
  ctx.globalAlpha = fade;
  ctx.strokeStyle = preview.color;
  ctx.shadowColor = preview.color;
  ctx.shadowBlur = preview.width * 2;
  ctx.lineWidth = preview.width;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.beginPath();
  pts.forEach(([x, y], i) => (i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)));
  ctx.stroke();
  ctx.restore();
}

/**
 * Paint order: highlighter underneath, then everything else in sequence order, then live
 * previews and the laser on top — the same order the Flutter painter uses.
 */
export function drawBoard(
  ctx: CanvasRenderingContext2D,
  page: BoardPage,
  items: Iterable<BoardItem>,
  previews: Iterable<Preview>,
  now: number,
): void {
  const { width, height } = ctx.canvas;
  ctx.save();
  ctx.clearRect(0, 0, width, height);
  ctx.scale(width / BOARD_WIDTH, height / BOARD_HEIGHT);
  drawBackground(ctx, page);
  const onPage = [...items].filter((i) => i.pageId === page.id);
  for (const item of onPage)
    if (item.kind === 'stroke' && PEN_STYLES[item.tool].underlay) drawItem(ctx, item);
  for (const item of onPage)
    if (!(item.kind === 'stroke' && PEN_STYLES[item.tool].underlay)) drawItem(ctx, item);
  for (const p of previews) {
    if (p.tool === 'laser') drawLaser(ctx, p, now);
    else drawPen(ctx, p.tool, p.color, p.width, p.points);
  }
  ctx.restore();
}
