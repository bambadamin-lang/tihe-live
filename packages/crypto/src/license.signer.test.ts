import { generateKeyPairSync } from 'node:crypto';
import { describe, expect, it } from 'vitest';

import {
  loadPublicKey,
  publicKeyRaw,
  signContainerHeader,
  signLicense,
  verifyLicense,
  type LicensePayloadWire,
} from './license.signer.js';

function keypair() {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  return {
    privateBase64: privateKey.export({ format: 'der', type: 'pkcs8' }).toString('base64'),
    publicBase64: publicKey.export({ format: 'der', type: 'spki' }).toString('base64'),
  };
}

const payload = (overrides: Partial<LicensePayloadWire> = {}): LicensePayloadWire => ({
  v: 1,
  license_id: 'lic_01J8ZQK5T9XVWR3M2N4P6H8B7C',
  user_id: 'usr_01J8ZQK5T9XVWR3M2N4P6H8B7C',
  device_ids: ['dev_01J8ZQK5T9XVWR3M2N4P6H8B7C'],
  course_ids: ['crs_01J8ZQK5T9XVWR3M2N4P6H8B7C'],
  video_ids: [],
  not_before: '2026-09-01T00:00:00.000Z',
  not_after: '2026-10-01T00:00:00.000Z',
  max_devices: 2,
  max_concurrent_streams: 1,
  offline_window_days: 30,
  revocation_epoch: 3,
  issued_at: '2026-09-01T00:00:00.000Z',
  server_time: '2026-09-01T00:00:00.000Z',
  ...overrides,
});

describe('signLicense', () => {
  it('produces a signature that verifies', () => {
    const { privateBase64, publicBase64 } = keypair();
    const signed = signLicense(payload(), privateBase64);

    expect(verifyLicense(signed.signedBytes, signed.signature, publicBase64)).toBe(true);
  });

  it('produces a 64-byte Ed25519 signature', () => {
    const { privateBase64 } = keypair();
    expect(signLicense(payload(), privateBase64).signature).toHaveLength(64);
  });

  it('fails verification under a different public key', () => {
    // The attack this blocks: mint your own licence with your own keypair.
    const real = keypair();
    const forger = keypair();
    const signed = signLicense(payload(), forger.privateBase64);

    expect(verifyLicense(signed.signedBytes, signed.signature, real.publicBase64)).toBe(false);
  });

  it('fails verification when a signed byte is altered', () => {
    const { privateBase64, publicBase64 } = keypair();
    const signed = signLicense(payload(), privateBase64);

    signed.signedBytes[10] ^= 0xff;

    expect(verifyLicense(signed.signedBytes, signed.signature, publicBase64)).toBe(false);
  });

  it('fails verification when the signature is altered', () => {
    const { privateBase64, publicBase64 } = keypair();
    const signed = signLicense(payload(), privateBase64);

    signed.signature[0] ^= 0x01;

    expect(verifyLicense(signed.signedBytes, signed.signature, publicBase64)).toBe(false);
  });

  it('signs different expiries to different bytes', () => {
    // If two different expiries produced identical signed bytes, extending a licence would be free.
    const { privateBase64 } = keypair();

    const a = signLicense(payload({ not_after: '2026-10-01T00:00:00.000Z' }), privateBase64);
    const b = signLicense(payload({ not_after: '2099-10-01T00:00:00.000Z' }), privateBase64);

    expect(a.signedBytes.equals(b.signedBytes)).toBe(false);
    expect(a.signature.equals(b.signature)).toBe(false);
  });

  it('is deterministic for identical payloads', () => {
    // Ed25519 is deterministic, which makes a stored blob reproducible for support purposes.
    const { privateBase64 } = keypair();

    const a = signLicense(payload(), privateBase64);
    const b = signLicense(payload(), privateBase64);

    expect(a.signature.equals(b.signature)).toBe(true);
  });
});

describe('key loading', () => {
  it('accepts a DER key', () => {
    const { publicBase64 } = keypair();
    expect(() => loadPublicKey(publicBase64)).not.toThrow();
  });

  it('accepts a raw 32-byte key', () => {
    // Keys pasted from other tooling often arrive raw rather than DER-wrapped.
    const { publicBase64 } = keypair();
    const raw = publicKeyRaw(publicBase64);

    expect(raw).toHaveLength(32);
    expect(() => loadPublicKey(raw.toString('base64'))).not.toThrow();
  });

  it('round trips DER to raw and back to the same key', () => {
    const { publicBase64 } = keypair();
    const raw = publicKeyRaw(publicBase64);

    expect(publicKeyRaw(raw.toString('base64')).equals(raw)).toBe(true);
  });
});

describe('signContainerHeader', () => {
  it('signs header bytes verifiably', () => {
    // A .tihex header carries the expiry and device binding; without a valid signature over it, a
    // student could extend their own access by editing the file.
    const { privateBase64, publicBase64 } = keypair();
    const header = Buffer.from('pretend this is CBOR', 'utf8');

    const signature = signContainerHeader(header, privateBase64);

    expect(verifyLicense(header, signature, publicBase64)).toBe(true);

    header[0] ^= 0xff;
    expect(verifyLicense(header, signature, publicBase64)).toBe(false);
  });
});
