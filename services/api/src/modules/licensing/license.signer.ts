import { createPrivateKey, createPublicKey, sign, verify } from 'node:crypto';

import { encode as cborEncode } from 'cbor-x';

/**
 * Ed25519 licence signing.
 *
 * ⚠️ The encoding here must match `LicensePayload` in `packages/secure-core/src/license.rs`. The
 * device verifies the signature over these exact bytes, offline, against a public key compiled
 * into the app. A field renamed on one side and not the other produces licences that no device
 * accepts — and the failure looks like "expired" to the student.
 *
 * Note the deliberate asymmetry: this module can sign, and `secure-core` cannot. The client holds
 * only the public key, so a fully reverse-engineered client still cannot mint a licence.
 */

/** Field order is fixed: it is part of what gets signed. */
export interface LicensePayloadWire {
  v: number;
  license_id: string;
  user_id: string;
  device_ids: string[];
  course_ids: string[];
  video_ids: string[];
  not_before: string;
  not_after: string;
  max_devices: number;
  max_concurrent_streams: number;
  offline_window_days: number;
  revocation_epoch: number;
  issued_at: string;
  server_time: string;
}

const PKCS8_ED25519_PREFIX = Buffer.from('302e020100300506032b657004220420', 'hex');
const SPKI_ED25519_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

/**
 * Accepts either a base64 DER key (as `generate-secrets.sh` emits) or 32 raw bytes.
 *
 * Both forms turn up in practice — the script produces DER, while a key pasted from another tool is
 * often raw — and guessing wrong yields an unhelpful OpenSSL error at boot.
 */
export function loadPrivateKey(base64: string) {
  const bytes = Buffer.from(base64, 'base64');
  if (bytes.length === 32) {
    return createPrivateKey({
      key: Buffer.concat([PKCS8_ED25519_PREFIX, bytes]),
      format: 'der',
      type: 'pkcs8',
    });
  }
  return createPrivateKey({ key: bytes, format: 'der', type: 'pkcs8' });
}

export function loadPublicKey(base64: string) {
  const bytes = Buffer.from(base64, 'base64');
  if (bytes.length === 32) {
    return createPublicKey({
      key: Buffer.concat([SPKI_ED25519_PREFIX, bytes]),
      format: 'der',
      type: 'spki',
    });
  }
  return createPublicKey({ key: bytes, format: 'der', type: 'spki' });
}

/** The raw 32 bytes, which is what gets embedded in the Flutter client. */
export function publicKeyRaw(base64: string): Buffer {
  const key = loadPublicKey(base64);
  return key.export({ format: 'der', type: 'spki' }).subarray(SPKI_ED25519_PREFIX.length);
}

export interface SignedLicense {
  payload: LicensePayloadWire;
  /** The exact bytes the signature covers. */
  signedBytes: Buffer;
  signature: Buffer;
}

/**
 * Signs a licence payload.
 *
 * The signed bytes are returned alongside the signature and stored verbatim. Re-encoding at
 * verification time would risk a byte-level difference — a map ordering, an integer width — that
 * fails a signature over a licence that is perfectly valid.
 */
export function signLicense(payload: LicensePayloadWire, privateKeyBase64: string): SignedLicense {
  const signedBytes = Buffer.from(cborEncode(payload));
  const signature = sign(null, signedBytes, loadPrivateKey(privateKeyBase64));
  return { payload, signedBytes, signature };
}

/** Verification, used by tests and by support tooling that inspects an issued licence. */
export function verifyLicense(
  signedBytes: Buffer,
  signature: Buffer,
  publicKeyBase64: string,
): boolean {
  return verify(null, signedBytes, loadPublicKey(publicKeyBase64), signature);
}

/** Signs a `.tihex` container header. Same key, different payload. */
export function signContainerHeader(headerBytes: Buffer, privateKeyBase64: string): Buffer {
  return sign(null, headerBytes, loadPrivateKey(privateKeyBase64));
}
