/**
 * @tihe/crypto — server-side cryptography, in one place.
 *
 * Everything here runs on the server only. The device half of each operation lives in
 * `packages/secure-core` (Rust), and the two must stay byte-compatible — the committed fixtures in
 * `src/__fixtures__/` and `packages/secure-core/tests/wire_compat.rs` are what hold them together.
 *
 * Shared rather than API-local because the packager mints and wraps content keys, and duplicating a
 * key format is how it silently diverges. Read docs/03-content-protection.md before changing any of
 * it.
 */
export {
  generateContentKey,
  segmentIv,
  unwrapKeyForDevice,
  wrapKeyForDevice,
  x25519PrivateKeyFromRaw,
  x25519PublicKeyFromRaw,
} from './key-wrap.js';

export { unwrapContentKeyWithKek, wrapContentKeyWithKek } from './kek.js';

export {
  loadPrivateKey,
  loadPublicKey,
  publicKeyRaw,
  signContainerHeader,
  signLicense,
  verifyLicense,
  type LicensePayloadWire,
  type SignedLicense,
} from './license.signer.js';
