import { z } from 'zod';

/**
 * Adobe Connect–style stage layouts: pods placed on a 12 × 12 grid. See
 * docs/11-live-classroom.md §5.
 *
 * Coordinates are measured from the *start* edge, not the left, so one layout renders
 * correctly in RTL — where the start edge is on the right — without a mirrored copy.
 */
export const LAYOUT_GRID = 12;
export const MAX_PODS = 8;

export const POD_KINDS = [
  'speaker',
  'gallery',
  'screen',
  'whiteboard',
  'chat',
  'participants',
  'hands',
] as const;
export const podKindSchema = z.enum(POD_KINDS);
export type PodKind = z.infer<typeof podKindSchema>;

/** Pods that show class content. The rest show people, so they stay out of recordings. */
export const MEDIA_POD_KINDS: readonly PodKind[] = ['screen', 'whiteboard', 'speaker', 'gallery'];

export const podSchema = z.object({
  id: z.string().min(1).max(32),
  kind: podKindSchema,
  x: z
    .number()
    .int()
    .min(0)
    .max(LAYOUT_GRID - 1),
  y: z
    .number()
    .int()
    .min(0)
    .max(LAYOUT_GRID - 1),
  w: z.number().int().min(1).max(LAYOUT_GRID),
  h: z.number().int().min(1).max(LAYOUT_GRID),
});
export type Pod = z.infer<typeof podSchema>;

export const LAYOUT_PRESET_KEYS = [
  'lecture',
  'presentation',
  'whiteboard',
  'discussion',
  'split',
  'qa',
] as const;
export const layoutPresetKeySchema = z.enum(LAYOUT_PRESET_KEYS);
export type LayoutPresetKey = z.infer<typeof layoutPresetKeySchema>;

/**
 * Every reason a layout is unusable, empty when it is fine. Shared by the zod refinement below
 * and the layout editor, which shows these while the teacher drags pods around.
 */
export function layoutProblems(pods: readonly Pod[]): string[] {
  const problems: string[] = [];
  if (pods.length === 0) problems.push('a layout needs at least one pod');
  if (pods.length > MAX_PODS) problems.push(`a layout holds at most ${MAX_PODS} pods`);

  const ids = new Set<string>();
  const kinds = new Set<PodKind>();
  for (const pod of pods) {
    if (ids.has(pod.id)) problems.push(`duplicate pod id ${pod.id}`);
    ids.add(pod.id);
    if (kinds.has(pod.kind)) problems.push(`more than one ${pod.kind} pod`);
    kinds.add(pod.kind);
    if (pod.x + pod.w > LAYOUT_GRID || pod.y + pod.h > LAYOUT_GRID) {
      problems.push(`pod ${pod.id} extends past the grid`);
    }
  }

  for (let i = 0; i < pods.length; i++) {
    for (let j = i + 1; j < pods.length; j++) {
      const a = pods[i]!;
      const b = pods[j]!;
      const overlaps = a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
      if (overlaps) problems.push(`pods ${a.id} and ${b.id} overlap`);
    }
  }
  return problems;
}

export const layoutSchema = z
  .object({
    /** A preset key for presets, `lay_…` for a saved custom layout, `custom` for unsaved. */
    id: z.string().min(1).max(40),
    name: z.string().min(1).max(64),
    preset: layoutPresetKeySchema.nullable(),
    pods: z.array(podSchema),
  })
  .superRefine((layout, ctx) => {
    for (const message of layoutProblems(layout.pods)) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message, path: ['pods'] });
    }
  });
export type Layout = z.infer<typeof layoutSchema>;

const pod = (kind: PodKind, x: number, y: number, w: number, h: number): Pod => ({
  id: kind,
  kind,
  x,
  y,
  w,
  h,
});

/** The six recommended layouts. Names are what the teacher sees. */
export const LAYOUT_PRESETS: Readonly<Record<LayoutPresetKey, Layout>> = {
  lecture: {
    id: 'lecture',
    name: 'سخنرانی',
    preset: 'lecture',
    pods: [pod('speaker', 0, 0, 8, 12), pod('chat', 8, 0, 4, 7), pod('participants', 8, 7, 4, 5)],
  },
  presentation: {
    id: 'presentation',
    name: 'ارائه',
    preset: 'presentation',
    pods: [pod('screen', 0, 0, 9, 12), pod('speaker', 9, 0, 3, 4), pod('chat', 9, 4, 3, 8)],
  },
  whiteboard: {
    id: 'whiteboard',
    name: 'تخته سفید',
    preset: 'whiteboard',
    pods: [pod('whiteboard', 0, 0, 9, 12), pod('speaker', 9, 0, 3, 4), pod('chat', 9, 4, 3, 8)],
  },
  discussion: {
    id: 'discussion',
    name: 'گفتگو',
    preset: 'discussion',
    pods: [pod('gallery', 0, 0, 9, 12), pod('chat', 9, 0, 3, 7), pod('hands', 9, 7, 3, 5)],
  },
  split: {
    id: 'split',
    name: 'ترکیبی',
    preset: 'split',
    pods: [
      pod('screen', 0, 0, 6, 8),
      pod('whiteboard', 6, 0, 6, 8),
      pod('speaker', 0, 8, 3, 4),
      pod('gallery', 3, 8, 6, 4),
      pod('chat', 9, 8, 3, 4),
    ],
  },
  qa: {
    id: 'qa',
    name: 'پرسش و پاسخ',
    preset: 'qa',
    pods: [
      pod('speaker', 0, 0, 7, 8),
      pod('gallery', 0, 8, 7, 4),
      pod('hands', 7, 0, 5, 5),
      pod('chat', 7, 5, 5, 7),
    ],
  },
};

export const DEFAULT_LAYOUT_PRESET: LayoutPresetKey = 'lecture';

/**
 * The layout Egress records: the live layout without the pods that show people's names
 * (chat, participants, hands), so no student identity ends up in a library video.
 *
 * The biggest content pod takes the main area and the rest stack in a side column. Ties go to
 * screen, then whiteboard, then speaker, then gallery — the order in which a student would
 * rather see them on a small phone replay.
 */
export function deriveRecordingLayout(layout: Pick<Layout, 'pods'>): Layout {
  const priority = (kind: PodKind) => MEDIA_POD_KINDS.indexOf(kind);
  const media = layout.pods
    .filter((p) => MEDIA_POD_KINDS.includes(p.kind))
    .sort((a, b) => b.w * b.h - a.w * a.h || priority(a.kind) - priority(b.kind));

  const [main, ...rest] = media;
  if (!main) {
    return {
      id: 'recording',
      name: 'recording',
      preset: null,
      pods: [pod('speaker', 0, 0, 12, 12)],
    };
  }
  const side = rest.slice(0, 3);
  const mainWidth = side.length > 0 ? 9 : LAYOUT_GRID;
  return {
    id: 'recording',
    name: 'recording',
    preset: null,
    pods: [
      pod(main.kind, 0, 0, mainWidth, LAYOUT_GRID),
      ...side.map((p, i) => pod(p.kind, 9, i * 4, 3, 4)),
    ],
  };
}
