import { z } from 'zod';
import { id } from '../common.js';

/**
 * The shared whiteboard. See docs/11-live-classroom.md §6.
 *
 * Page space is a fixed 16:9 integer grid, so a stroke looks identical on a phone, a 4K
 * monitor and in the Egress recording. Integers keep messages small and make the Dart and
 * TypeScript renderers agree exactly.
 */
export const BOARD_WIDTH = 16000;
export const BOARD_HEIGHT = 9000;

export const MAX_STROKE_POINTS = 2000;
export const MAX_ITEMS_PER_PAGE = 10000;
export const MAX_PAGES = 50;
export const MAX_TEXT_LENGTH = 500;
/** Points per `wb.progress` batch — about 40 ms of fast drawing. */
export const MAX_PROGRESS_POINTS = 100;

export const PEN_TOOLS = ['pen', 'marker', 'highlighter'] as const;
export const penToolSchema = z.enum(PEN_TOOLS);
export type PenTool = z.infer<typeof penToolSchema>;

export const SHAPES = ['line', 'arrow', 'rect', 'ellipse'] as const;
export const shapeSchema = z.enum(SHAPES);
export type Shape = z.infer<typeof shapeSchema>;

/** Everything in the marker tray. Eraser and laser never produce stored items. */
export const BOARD_TOOLS = [...PEN_TOOLS, ...SHAPES, 'text', 'eraser', 'laser'] as const;
export type BoardTool = (typeof BOARD_TOOLS)[number];

/**
 * How each pen is drawn: perfect-freehand options plus opacity. The Flutter board
 * (`perfect_freehand`) and the Egress template (`perfect-freehand`) both read these, so a stroke
 * in the recording looks exactly as it did live. Sizes are multiples of the item's `width`.
 */
export interface PenStyle {
  thinning: number;
  smoothing: number;
  streamline: number;
  simulatePressure: boolean;
  opacity: number;
  /** Drawn beneath ink, multiplied, like a real highlighter over print. */
  underlay: boolean;
}
export const PEN_STYLES: Readonly<Record<PenTool, PenStyle>> = {
  pen: {
    thinning: 0.55,
    smoothing: 0.5,
    streamline: 0.45,
    simulatePressure: true,
    opacity: 1,
    underlay: false,
  },
  marker: {
    thinning: 0,
    smoothing: 0.6,
    streamline: 0.5,
    simulatePressure: false,
    opacity: 1,
    underlay: false,
  },
  highlighter: {
    thinning: 0,
    smoothing: 0.7,
    streamline: 0.6,
    simulatePressure: false,
    opacity: 0.35,
    underlay: true,
  },
};

/** Default widths in page units for each tool, what the marker tray starts with. */
export const DEFAULT_TOOL_WIDTH: Readonly<Record<PenTool | Shape | 'laser', number>> = {
  pen: 28,
  marker: 70,
  highlighter: 240,
  line: 28,
  arrow: 28,
  rect: 28,
  ellipse: 28,
  laser: 60,
};

/** Marker-tray colours: ink black, blue, red, green, orange, purple, highlighter yellow, white. */
export const BOARD_PALETTE = [
  '#1B1B1F',
  '#1F4FD8',
  '#D32F2F',
  '#2E7D32',
  '#F57C00',
  '#7B1FA2',
  '#FFD600',
  '#FFFFFF',
] as const;

export const colorSchema = z.string().regex(/^#[0-9A-Fa-f]{6}$/, 'must be #RRGGBB');

export const BOARD_BACKGROUNDS = ['plain', 'grid', 'lines', 'dots'] as const;

export const boardPageSchema = z.object({
  id: id('boardPage'),
  background: z.enum(BOARD_BACKGROUNDS),
});
export type BoardPage = z.infer<typeof boardPageSchema>;

const xSchema = z.number().int().min(0).max(BOARD_WIDTH);
const ySchema = z.number().int().min(0).max(BOARD_HEIGHT);
export const pointSchema = z.tuple([xSchema, ySchema]);

/** `[x0, y0, x1, y1, …]` — flat, because a nested array doubles the JSON size of a stroke. */
const flatPoints = (maxPoints: number) =>
  z
    .array(z.number().int())
    .min(2)
    .max(maxPoints * 2)
    .refine((pts) => pts.length % 2 === 0, 'points come in x,y pairs')
    .refine(
      (pts) => pts.every((v, i) => v >= 0 && v <= (i % 2 === 0 ? BOARD_WIDTH : BOARD_HEIGHT)),
      'points must lie on the page',
    );

const itemBase = {
  id: id('boardItem'),
  pageId: id('boardPage'),
  color: colorSchema,
};

export const strokeItemSchema = z.object({
  ...itemBase,
  kind: z.literal('stroke'),
  tool: penToolSchema,
  width: z.number().int().min(1).max(640),
  points: flatPoints(MAX_STROKE_POINTS),
});

export const shapeItemSchema = z.object({
  ...itemBase,
  kind: z.literal('shape'),
  shape: shapeSchema,
  width: z.number().int().min(1).max(640),
  fill: colorSchema.nullable(),
  from: pointSchema,
  to: pointSchema,
});

export const textItemSchema = z.object({
  ...itemBase,
  kind: z.literal('text'),
  /** Font size in page units (the page is 9000 high). */
  size: z.number().int().min(80).max(2000),
  /**
   * The text's top-right corner. Text runs in its own direction (a formula left to right, Persian
   * right to left, decided by its first strong character) and is right-aligned at this point.
   * Lines break on `\n`.
   */
  at: pointSchema,
  text: z.string().min(1).max(MAX_TEXT_LENGTH),
});

/** What a client sends. Ids are client-generated ULIDs so the drawer sees it instantly. */
export const boardItemInputSchema = z.discriminatedUnion('kind', [
  strokeItemSchema,
  shapeItemSchema,
  textItemSchema,
]);
export type BoardItemInput = z.infer<typeof boardItemInputSchema>;

/** What the server stores and broadcasts: the input plus its author and sequence number. */
const stored = { by: id('user'), seq: z.number().int().nonnegative() };
export const boardItemSchema = z.discriminatedUnion('kind', [
  strokeItemSchema.extend(stored),
  shapeItemSchema.extend(stored),
  textItemSchema.extend(stored),
]);
export type BoardItem = z.infer<typeof boardItemSchema>;

/**
 * A live-preview batch of an in-progress stroke, or a laser-pointer trail. Relayed to others,
 * never stored, and safe to drop under load — the committed `wb.add` is what counts.
 */
export const boardProgressSchema = z.object({
  type: z.literal('wb.progress'),
  strokeId: id('boardItem'),
  pageId: id('boardPage'),
  tool: z.enum([...PEN_TOOLS, 'laser']),
  color: colorSchema,
  width: z.number().int().min(1).max(640),
  /** Only the points added since the previous batch. */
  points: flatPoints(MAX_PROGRESS_POINTS),
  /** Last batch of this stroke; receivers drop their preview. */
  done: z.boolean(),
});
export type BoardProgress = z.infer<typeof boardProgressSchema>;

export const boardStateSchema = z.object({
  pages: z.array(boardPageSchema).min(1).max(MAX_PAGES),
  activePageId: id('boardPage'),
  items: z.array(boardItemSchema),
});
export type BoardState = z.infer<typeof boardStateSchema>;
