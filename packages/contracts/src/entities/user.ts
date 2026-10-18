import { z } from 'zod';
import { id, platformSchema, roleSchema } from '../common.js';

export const userSchema = z.object({
  id: id('user'),
  /** Masked for display (0912•••6789). The full number reaches a client only inside its owner's
   *  own watermark. */
  phoneMasked: z.string(),
  displayName: z.string().nullable(),
  role: roleSchema,
  status: z.enum(['active', 'suspended']),
  createdAt: z.string().datetime(),
});
export type User = z.infer<typeof userSchema>;

export const deviceSchema = z.object({
  id: id('device'),
  platform: platformSchema,
  /** User-chosen, e.g. "لپ‌تاپ خانه". Helps them pick which device to release. */
  name: z.string(),
  trustedAt: z.string().datetime().nullable(),
  revokedAt: z.string().datetime().nullable(),
  lastSeenAt: z.string().datetime().nullable(),
  /** Whether this is the device making the current request — so the UI can say "این دستگاه". */
  isCurrent: z.boolean(),
  /** How many videos this device holds offline, for the device manager screen. */
  offlineVideoCount: z.number().int().nonnegative(),
});
export type Device = z.infer<typeof deviceSchema>;
