import { classRoleSchema, type ClassRole } from '@tihe/contracts';
import { jwtVerify, SignJWT } from 'jose';
import { TokenVerifier } from 'livekit-server-sdk';
import { z } from 'zod';

/**
 * Gateway tickets: what a client presents in its first WebSocket message. Minted at join, valid
 * for two minutes, bound to one user and one session. Short so a ticket lifted from a log or a
 * crash report is useless; a reconnecting client simply joins again.
 */
export const TICKET_TTL_SECONDS = 120;
const AUDIENCE = 'tihe-live-gateway';

export interface GatewayIdentity {
  sessionId: string;
  userId: string;
  name: string;
  role: ClassRole;
}

const ticketClaims = z.object({
  sub: z.string(),
  sid: z.string(),
  name: z.string(),
  role: classRoleSchema,
});

export class TicketService {
  private readonly key: Uint8Array;
  private readonly livekit: TokenVerifier;

  constructor(secret: string, livekitKey: string, livekitSecret: string) {
    this.key = new TextEncoder().encode(secret);
    this.livekit = new TokenVerifier(livekitKey, livekitSecret);
  }

  async mint(
    identity: GatewayIdentity,
    now = new Date(),
  ): Promise<{ ticket: string; expiresAt: Date }> {
    const expiresAt = new Date(now.getTime() + TICKET_TTL_SECONDS * 1000);
    const ticket = await new SignJWT({
      sid: identity.sessionId,
      name: identity.name,
      role: identity.role,
    })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(identity.userId)
      .setAudience(AUDIENCE)
      .setIssuedAt(Math.floor(now.getTime() / 1000))
      .setExpirationTime(Math.floor(expiresAt.getTime() / 1000))
      .sign(this.key);
    return { ticket, expiresAt };
  }

  /**
   * A gateway ticket — or the LiveKit token Egress hands the recording template. The latter is
   * accepted only when LiveKit signed it for a hidden recorder in that room, so the template
   * needs no credential of ours in its URL.
   */
  async verify(ticket: string): Promise<GatewayIdentity | null> {
    try {
      const { payload } = await jwtVerify(ticket, this.key, {
        audience: AUDIENCE,
        algorithms: ['HS256'],
      });
      const claims = ticketClaims.safeParse(payload);
      if (claims.success) {
        return {
          sessionId: claims.data.sid,
          userId: claims.data.sub,
          name: claims.data.name,
          role: claims.data.role,
        };
      }
    } catch {
      // not ours; try LiveKit below
    }
    try {
      const grants = await this.livekit.verify(ticket);
      if (grants.video?.recorder && grants.video.room && grants.sub) {
        return {
          sessionId: grants.video.room,
          userId: grants.sub,
          name: 'recorder',
          role: 'recorder',
        };
      }
    } catch {
      // neither
    }
    return null;
  }
}
