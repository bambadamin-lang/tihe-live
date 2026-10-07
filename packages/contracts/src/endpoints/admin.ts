import { z } from 'zod';
import { id, paginated, phoneSchema, roleSchema } from '../common.js';
import { deviceSchema, userSchema } from '../entities/user.js';
import { passwordSchema } from './auth.js';

/**
 * Admin endpoints (ADR-0013, ADR-0014): accounts, the device limit, enrollments. Every route
 * requires role `admin`. Phone numbers go in and stay masked on the way out, here as everywhere.
 */

/** How many devices may be signed in to one account at once. */
export const deviceLimitSchema = z.number().int().min(1).max(20);

export const instituteSettingsSchema = z.object({
  /** Applies to every account without its own limit. */
  defaultMaxDevices: deviceLimitSchema,
});
export type InstituteSettings = z.infer<typeof instituteSettingsSchema>;

export const updateSettingsBodySchema = instituteSettingsSchema.partial();
export type UpdateSettingsBody = z.infer<typeof updateSettingsBodySchema>;

export const adminUserSchema = userSchema.extend({
  /** This account's own limit; null means the institute default applies. */
  maxDevices: deviceLimitSchema.nullable(),
  /** The limit actually enforced: maxDevices, or the default. */
  effectiveMaxDevices: deviceLimitSchema,
  signedInDevices: z.number().int().nonnegative(),
  enrolledCourses: z.number().int().nonnegative(),
});
export type AdminUser = z.infer<typeof adminUserSchema>;

export const adminUserListQuerySchema = z.object({
  /** A name, or a phone number in any form students type it. */
  query: z.string().trim().max(64).optional(),
  role: roleSchema.optional(),
  limit: z.coerce.number().int().min(1).max(100).default(30),
  cursor: z.string().optional(),
});
export type AdminUserListQuery = z.infer<typeof adminUserListQuerySchema>;

export const adminUserListSchema = paginated(adminUserSchema);
export type AdminUserList = z.infer<typeof adminUserListSchema>;

export const adminEnrollmentSchema = z.object({
  courseId: id('course'),
  courseTitle: z.string(),
  status: z.enum(['active', 'suspended', 'completed']),
  enrolledAt: z.string().datetime(),
  expiresAt: z.string().datetime().nullable(),
});
export type AdminEnrollment = z.infer<typeof adminEnrollmentSchema>;

export const adminUserDetailSchema = adminUserSchema.extend({
  /** Signed-in devices first, then the rest the account has used. */
  devices: z.array(deviceSchema),
  enrollments: z.array(adminEnrollmentSchema),
});
export type AdminUserDetail = z.infer<typeof adminUserDetailSchema>;

export const createUserBodySchema = z.object({
  phone: phoneSchema,
  displayName: z.string().trim().min(1).max(80),
  role: roleSchema.default('student'),
  password: passwordSchema,
  /** Ask the student to choose their own password at first sign-in. */
  mustChangePassword: z.boolean().default(true),
  maxDevices: deviceLimitSchema.nullable().default(null),
});
export type CreateUserBody = z.infer<typeof createUserBodySchema>;

export const updateUserBodySchema = z
  .object({
    displayName: z.string().trim().min(1).max(80),
    role: roleSchema,
    status: z.enum(['active', 'suspended']),
    /** null returns the account to the institute default. */
    maxDevices: deviceLimitSchema.nullable(),
    /** A new temporary password. Signs the account out everywhere. */
    password: passwordSchema,
    mustChangePassword: z.boolean(),
  })
  .partial();
export type UpdateUserBody = z.infer<typeof updateUserBodySchema>;

export const enrollBodySchema = z.object({
  courseId: id('course'),
  expiresAt: z.string().datetime().optional(),
});
export type EnrollBody = z.infer<typeof enrollBodySchema>;

export const adminCourseSchema = z.object({
  id: id('course'),
  title: z.string(),
  status: z.enum(['draft', 'published', 'archived']),
  enrolledCount: z.number().int().nonnegative(),
});
export type AdminCourse = z.infer<typeof adminCourseSchema>;
