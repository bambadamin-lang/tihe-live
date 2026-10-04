import { z } from 'zod';
import { id, phoneSchema, platformSchema } from '../common.js';
import { deviceSchema, userSchema } from '../entities/user.js';

/**
 * Device identity presented at sign-in.
 *
 * `publicKey` is the device's X25519 public half. Its private counterpart is generated on the
 * device and sealed in Android Keystore / Windows DPAPI, and never leaves. Content keys are
 * wrapped to this key, which is what makes a copied .tihex file useless elsewhere.
 */
export const deviceIdentitySchema = z.object({
  fingerprint: z.string().min(16).max(256),
  platform: platformSchema,
  name: z.string().min(1).max(64),
  publicKey: z.string().base64(),
  appVersion: z.string().max(32).optional(),
  osVersion: z.string().max(64).optional(),
});
export type DeviceIdentity = z.infer<typeof deviceIdentitySchema>;

/**
 * A new password. The server applies the full policy (no phone number, not one repeated
 * character) and answers PASSWORD_TOO_WEAK; this is the shape both sides agree on.
 */
export const passwordSchema = z.string().min(8).max(128);

/**
 * Phone + password sign-in (ADR-0013). The password is not checked against the policy here: a
 * sign-in must not reveal what the policy is, only whether the pair is right.
 */
export const loginBodySchema = z.object({
  phone: phoneSchema,
  password: z.string().min(1).max(128),
  device: deviceIdentitySchema,
});
export type LoginBody = z.infer<typeof loginBodySchema>;

/** One of the devices signed in to the account, as offered when the limit is reached. */
export const signedInDeviceSchema = z.object({
  id: id('device'),
  platform: platformSchema,
  name: z.string(),
  signedInAt: z.string().datetime().nullable(),
  lastSeenAt: z.string().datetime().nullable(),
});
export type SignedInDevice = z.infer<typeof signedInDeviceSchema>;

/**
 * `details` of DEVICE_LIMIT_REACHED on sign-in (ADR-0014). The ticket proves the password was
 * right, so the student can sign one device out and continue without typing it again. It is
 * bound to the device that asked and lasts five minutes.
 */
export const deviceLimitDetailsSchema = z.object({
  limit: z.number().int().positive(),
  devices: z.array(signedInDeviceSchema),
  ticket: z.string(),
  ticketExpiresAt: z.string().datetime(),
});
export type DeviceLimitDetails = z.infer<typeof deviceLimitDetailsSchema>;

export const replaceDeviceBodySchema = z.object({
  ticket: z.string().min(1),
  signOutDeviceId: id('device'),
  device: deviceIdentitySchema,
});
export type ReplaceDeviceBody = z.infer<typeof replaceDeviceBodySchema>;

export const changePasswordBodySchema = z.object({
  currentPassword: z.string().min(1).max(128),
  newPassword: passwordSchema,
  /** Signing the other devices out is what a student changing a leaked password needs. */
  signOutOtherDevices: z.boolean().default(true),
});
export type ChangePasswordBody = z.infer<typeof changePasswordBodySchema>;

export const tokenPairSchema = z.object({
  accessToken: z.string(),
  refreshToken: z.string(),
  accessExpiresAt: z.string().datetime(),
  refreshExpiresAt: z.string().datetime(),
});
export type TokenPair = z.infer<typeof tokenPairSchema>;

export const authSessionSchema = z.object({
  tokens: tokenPairSchema,
  user: userSchema,
  device: deviceSchema,
});
export type AuthSession = z.infer<typeof authSessionSchema>;

export const refreshBodySchema = z.object({
  refreshToken: z.string(),
});
export type RefreshBody = z.infer<typeof refreshBodySchema>;

export const meResponseSchema = z.object({
  user: userSchema,
  device: deviceSchema,
  /** Client compares this with its stored epoch to detect a revocation it has not seen. */
  revocationEpoch: z.number().int().nonnegative(),
});
export type MeResponse = z.infer<typeof meResponseSchema>;

export const registerDeviceBodySchema = deviceIdentitySchema;

export const releaseDeviceParamsSchema = z.object({
  id: id('device'),
});
