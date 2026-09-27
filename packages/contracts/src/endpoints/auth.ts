import { z } from 'zod';
import { id, phoneSchema, platformSchema } from '../common.js';
import { deviceSchema, userSchema } from '../entities/user.js';

export const otpRequestBodySchema = z.object({
  phone: phoneSchema,
});
export type OtpRequestBody = z.infer<typeof otpRequestBodySchema>;

/**
 * Deliberately identical whether or not the phone number belongs to a registered user —
 * otherwise this endpoint enumerates the institute's students.
 */
export const otpRequestResponseSchema = z.object({
  requestId: z.string(),
  expiresInSeconds: z.number().int().positive(),
  resendAfterSeconds: z.number().int().positive(),
  /** Only in development, where SMS_PROVIDER=console. Never populated in production. */
  devCode: z.string().optional(),
});
export type OtpRequestResponse = z.infer<typeof otpRequestResponseSchema>;

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

export const otpVerifyBodySchema = z.object({
  phone: phoneSchema,
  code: z.string().regex(/^\d{4,8}$/),
  device: deviceIdentitySchema,
});
export type OtpVerifyBody = z.infer<typeof otpVerifyBodySchema>;

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
