import { createHash, createHmac, timingSafeEqual } from 'node:crypto';

/**
 * Verifies a LiveKit webhook.
 *
 * LiveKit signs webhooks with a JWT whose `sha256` claim is the digest of the request body. Checking
 * only the JWT signature would leave the body swappable, so both are verified.
 *
 * Why this matters more than a typical webhook: a forged `egress_ended` injects an arbitrary
 * recording into the library, attributed to a real course, visible to every enrolled student.
 *
 * The raw body is required, which is why the API registers a raw-body parser for this route.
 */

export type VerifyResult =
  { valid: true; payload: Record<string, unknown> } | { valid: false; reason: string };

function base64UrlDecode(input: string): Buffer {
  return Buffer.from(input.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

export function verifyLivekitWebhook(
  authorizationHeader: string | undefined,
  rawBody: Buffer,
  apiKey: string,
  apiSecret: string,
  options: { allowUnsigned?: boolean; now?: Date } = {},
): VerifyResult {
  if (!authorizationHeader) {
    // Development convenience so infra/scripts/fake-egress.sh works without LiveKit running.
    // Configuration refuses to start with this enabled in production.
    if (options.allowUnsigned) {
      try {
        return { valid: true, payload: JSON.parse(rawBody.toString('utf8')) };
      } catch {
        return { valid: false, reason: 'unsigned request with unparseable body' };
      }
    }
    return { valid: false, reason: 'missing authorization header' };
  }

  const token = authorizationHeader.replace(/^Bearer\s+/i, '').trim();
  const parts = token.split('.');
  if (parts.length !== 3) {
    if (options.allowUnsigned) {
      try {
        return { valid: true, payload: JSON.parse(rawBody.toString('utf8')) };
      } catch {
        return { valid: false, reason: 'malformed token and unparseable body' };
      }
    }
    return { valid: false, reason: 'malformed JWT' };
  }

  const [headerB64, payloadB64, signatureB64] = parts as [string, string, string];

  const expected = createHmac('sha256', apiSecret).update(`${headerB64}.${payloadB64}`).digest();
  const provided = base64UrlDecode(signatureB64);

  if (expected.length !== provided.length || !timingSafeEqual(expected, provided)) {
    return { valid: false, reason: 'signature mismatch' };
  }

  let claims: { iss?: string; sha256?: string; exp?: number };
  try {
    claims = JSON.parse(base64UrlDecode(payloadB64).toString('utf8'));
  } catch {
    return { valid: false, reason: 'unparseable claims' };
  }

  if (claims.iss !== apiKey) {
    return { valid: false, reason: 'issuer mismatch' };
  }

  const now = Math.floor((options.now?.getTime() ?? Date.now()) / 1000);
  if (claims.exp !== undefined && claims.exp < now) {
    return { valid: false, reason: 'token expired' };
  }

  // The body digest is the part that stops a valid token being replayed with different content.
  if (claims.sha256) {
    const bodyDigest = createHash('sha256').update(rawBody).digest('base64');
    if (bodyDigest !== claims.sha256) {
      return { valid: false, reason: 'body digest mismatch' };
    }
  }

  try {
    return { valid: true, payload: JSON.parse(rawBody.toString('utf8')) };
  } catch {
    return { valid: false, reason: 'unparseable body' };
  }
}
