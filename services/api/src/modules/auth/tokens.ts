import { createHash, randomBytes } from 'node:crypto';

import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  ACCESS_TOKEN_AUDIENCE,
  ACCESS_TOKEN_ISSUER,
  type Role,
  type TokenPair,
} from '@tihe/contracts';
import { newId, type Prisma } from '@tihe/db';
import { z } from 'zod';

import type { PrismaService } from '../../common/prisma.service.js';
import type { Env } from '../../config/configuration.js';

type Db = PrismaService | Prisma.TransactionClient;

/** Device-limit tickets carry their own audience, so one can never pass as an access token. */
const TICKET_AUDIENCE = 'tihe-device-limit';
const TICKET_TTL_SECONDS = 5 * 60;

const accessClaimsSchema = z.object({
  sub: z.string(),
  did: z.string(),
  sid: z.string(),
  role: z.enum(['student', 'teacher', 'admin']),
});
export type AccessClaims = z.infer<typeof accessClaimsSchema>;

const ticketClaimsSchema = z.object({ sub: z.string(), fp: z.string() });

/**
 * Access tokens, refresh tokens and device-limit tickets.
 *
 * Access tokens carry what services/live requires of them (`accessTokenClaimsSchema` in
 * @tihe/contracts: `role`, `iss`, `aud`) plus `sid`, the device's current session, so signing a
 * device out ends its tokens at once (ADR-0014).
 */
@Injectable()
export class TokenService {
  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService<Env, true>,
  ) {}

  get refreshTtlMs(): number {
    return parseDuration(this.config.getOrThrow('REFRESH_TOKEN_TTL', { infer: true }));
  }

  async issue(
    db: Db,
    who: { userId: string; role: Role; deviceId: string; sessionId: string },
  ): Promise<TokenPair> {
    const accessTtl = this.config.getOrThrow('ACCESS_TOKEN_TTL', { infer: true });

    const accessToken = await this.jwt.signAsync(
      { sub: who.userId, did: who.deviceId, sid: who.sessionId, role: who.role },
      { expiresIn: accessTtl, issuer: ACCESS_TOKEN_ISSUER, audience: ACCESS_TOKEN_AUDIENCE },
    );

    const refreshToken = randomBytes(48).toString('base64url');
    const refreshExpiresAt = new Date(Date.now() + this.refreshTtlMs);

    await db.refreshToken.create({
      data: {
        id: newId('refreshToken'),
        userId: who.userId,
        deviceId: who.deviceId,
        tokenHash: hashRefreshToken(refreshToken),
        expiresAt: refreshExpiresAt,
      },
    });

    const decoded = this.jwt.decode<{ exp: number }>(accessToken);

    return {
      accessToken,
      refreshToken,
      accessExpiresAt: new Date(decoded.exp * 1000).toISOString(),
      refreshExpiresAt: refreshExpiresAt.toISOString(),
    };
  }

  /** Null for anything that is not a current access token of this API. */
  async verifyAccess(token: string): Promise<AccessClaims | null> {
    try {
      const payload: unknown = await this.jwt.verifyAsync(token, {
        issuer: ACCESS_TOKEN_ISSUER,
        audience: ACCESS_TOKEN_AUDIENCE,
      });
      const claims = accessClaimsSchema.safeParse(payload);
      return claims.success ? claims.data : null;
    } catch {
      return null;
    }
  }

  /**
   * A five-minute proof that this device got the password right, so the student can sign another
   * device out and continue without typing it again. Bound to the device that asked.
   */
  async deviceLimitTicket(
    userId: string,
    fingerprintHash: string,
  ): Promise<{ ticket: string; expiresAt: string }> {
    const ticket = await this.jwt.signAsync(
      { sub: userId, fp: fingerprintHash },
      { expiresIn: TICKET_TTL_SECONDS, issuer: ACCESS_TOKEN_ISSUER, audience: TICKET_AUDIENCE },
    );
    const { exp } = this.jwt.decode<{ exp: number }>(ticket);
    return { ticket, expiresAt: new Date(exp * 1000).toISOString() };
  }

  async verifyDeviceLimitTicket(
    ticket: string,
  ): Promise<{ userId: string; fingerprintHash: string } | null> {
    try {
      const payload: unknown = await this.jwt.verifyAsync(ticket, {
        issuer: ACCESS_TOKEN_ISSUER,
        audience: TICKET_AUDIENCE,
      });
      const claims = ticketClaimsSchema.safeParse(payload);
      return claims.success ? { userId: claims.data.sub, fingerprintHash: claims.data.fp } : null;
    } catch {
      return null;
    }
  }
}

/**
 * Refresh tokens are stored hashed, not encrypted: the API never needs to read one back, only to
 * recognise it. SHA-256 rather than Argon2 because these are 48 random bytes, not a password —
 * there is nothing to brute-force, and the lookup is on the hot path.
 */
export function hashRefreshToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/** Parses the `15m` / `30d` forms used in configuration. */
export function parseDuration(value: string): number {
  const match = /^(\d+)([smhd])$/.exec(value.trim());
  if (!match) throw new Error(`invalid duration: ${value}`);
  const amount = Number(match[1]);
  const unit = match[2];
  const multipliers: Record<string, number> = {
    s: 1000,
    m: 60_000,
    h: 3_600_000,
    d: 86_400_000,
  };
  const multiplier = unit === undefined ? undefined : multipliers[unit];
  if (multiplier === undefined) throw new Error(`invalid duration unit in: ${value}`);
  return amount * multiplier;
}
