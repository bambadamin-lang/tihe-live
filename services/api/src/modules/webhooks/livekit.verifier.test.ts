import { createHash, createHmac } from 'node:crypto';
import { describe, expect, it } from 'vitest';

import { verifyLivekitWebhook } from './livekit.verifier.js';

const API_KEY = 'devkey';
const API_SECRET = 'devsecret_for_tests_only_0000000000';

const b64url = (buf: Buffer | string) =>
  Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

function signedRequest(
  body: object,
  overrides: { secret?: string; iss?: string; exp?: number; sha256?: string } = {},
) {
  const rawBody = Buffer.from(JSON.stringify(body));
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const claims = b64url(
    JSON.stringify({
      iss: overrides.iss ?? API_KEY,
      exp: overrides.exp ?? Math.floor(Date.now() / 1000) + 300,
      sha256: overrides.sha256 ?? createHash('sha256').update(rawBody).digest('base64'),
    }),
  );
  const signature = b64url(
    createHmac('sha256', overrides.secret ?? API_SECRET)
      .update(`${header}.${claims}`)
      .digest(),
  );

  return { rawBody, token: `${header}.${claims}.${signature}` };
}

const body = { event: 'egress_ended', egressInfo: { egressId: 'EG_1' } };

describe('verifyLivekitWebhook', () => {
  it('accepts a correctly signed request', () => {
    const { rawBody, token } = signedRequest(body);

    const result = verifyLivekitWebhook(token, rawBody, API_KEY, API_SECRET);

    expect(result.valid).toBe(true);
    expect(result.valid && result.payload).toMatchObject({ event: 'egress_ended' });
  });

  it('accepts a Bearer-prefixed header', () => {
    const { rawBody, token } = signedRequest(body);
    expect(verifyLivekitWebhook(`Bearer ${token}`, rawBody, API_KEY, API_SECRET).valid).toBe(true);
  });

  it('rejects a signature made with the wrong secret', () => {
    const { rawBody, token } = signedRequest(body, { secret: 'the-wrong-secret-entirely-000000' });

    const result = verifyLivekitWebhook(token, rawBody, API_KEY, API_SECRET);

    expect(result).toEqual({ valid: false, reason: 'signature mismatch' });
  });

  it('rejects a swapped body even when the token is valid', () => {
    // This is the attack the sha256 claim exists for: a captured token replayed with a forged
    // recording would otherwise publish arbitrary video into a real course.
    const { token } = signedRequest(body);
    const forged = Buffer.from(
      JSON.stringify({ event: 'egress_ended', egressInfo: { egressId: 'EG_FORGED' } }),
    );

    const result = verifyLivekitWebhook(token, forged, API_KEY, API_SECRET);

    expect(result).toEqual({ valid: false, reason: 'body digest mismatch' });
  });

  it('rejects a mismatched issuer', () => {
    const { rawBody, token } = signedRequest(body, { iss: 'someone-else' });

    expect(verifyLivekitWebhook(token, rawBody, API_KEY, API_SECRET)).toEqual({
      valid: false,
      reason: 'issuer mismatch',
    });
  });

  it('rejects an expired token', () => {
    const { rawBody, token } = signedRequest(body, {
      exp: Math.floor(Date.now() / 1000) - 10,
    });

    expect(verifyLivekitWebhook(token, rawBody, API_KEY, API_SECRET)).toEqual({
      valid: false,
      reason: 'token expired',
    });
  });

  it('rejects a missing header when unsigned requests are not allowed', () => {
    expect(verifyLivekitWebhook(undefined, Buffer.from('{}'), API_KEY, API_SECRET)).toEqual({
      valid: false,
      reason: 'missing authorization header',
    });
  });

  it('rejects a malformed token', () => {
    expect(
      verifyLivekitWebhook('not.a.jwt.at.all', Buffer.from('{}'), API_KEY, API_SECRET).valid,
    ).toBe(false);
  });

  it('accepts an unsigned request only when explicitly allowed', () => {
    // How infra/scripts/fake-egress.sh drives the pipeline with no LiveKit running. Configuration
    // refuses to boot with this enabled in production.
    const rawBody = Buffer.from(JSON.stringify(body));

    expect(
      verifyLivekitWebhook(undefined, rawBody, API_KEY, API_SECRET, { allowUnsigned: true }).valid,
    ).toBe(true);
  });

  it('still rejects an unparseable body when unsigned requests are allowed', () => {
    expect(
      verifyLivekitWebhook(undefined, Buffer.from('not json'), API_KEY, API_SECRET, {
        allowUnsigned: true,
      }).valid,
    ).toBe(false);
  });
});
