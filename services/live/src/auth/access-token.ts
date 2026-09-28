import {
  ACCESS_TOKEN_AUDIENCE,
  ACCESS_TOKEN_ISSUER,
  accessTokenClaimsSchema,
  type Role,
} from '@tihe/contracts';
import { jwtVerify, SignJWT } from 'jose';

/** Who is calling, as established from an access token issued by services/api. */
export interface Caller {
  userId: string;
  accountRole: Role;
  deviceId: string;
}

/**
 * Verifies services/api access tokens (ADR-0012). An interface so the HS256 shared secret can
 * later be swapped for EdDSA + JWKS without touching any caller.
 */
export interface AccessTokenVerifier {
  verify(token: string): Promise<Caller | null>;
}
export const ACCESS_TOKEN_VERIFIER = Symbol('ACCESS_TOKEN_VERIFIER');

export class Hs256AccessTokenVerifier implements AccessTokenVerifier {
  private readonly key: Uint8Array;

  constructor(secret: string) {
    this.key = new TextEncoder().encode(secret);
  }

  async verify(token: string): Promise<Caller | null> {
    try {
      const { payload } = await jwtVerify(token, this.key, {
        algorithms: ['HS256'],
        issuer: ACCESS_TOKEN_ISSUER,
        audience: ACCESS_TOKEN_AUDIENCE,
      });
      const claims = accessTokenClaimsSchema.safeParse(payload);
      if (!claims.success) return null;
      return { userId: claims.data.sub, accountRole: claims.data.role, deviceId: claims.data.did };
    } catch {
      return null;
    }
  }
}

/**
 * Mints an access token the way services/api does. For development and tests only — the
 * dev-token script uses it so the classroom can be driven before the API exists.
 */
export async function mintDevAccessToken(
  secret: string,
  caller: Caller,
  ttlSeconds = 3600,
): Promise<string> {
  return new SignJWT({ role: caller.accountRole, did: caller.deviceId })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(caller.userId)
    .setIssuer(ACCESS_TOKEN_ISSUER)
    .setAudience(ACCESS_TOKEN_AUDIENCE)
    .setIssuedAt()
    .setExpirationTime(`${ttlSeconds}s`)
    .sign(new TextEncoder().encode(secret));
}
