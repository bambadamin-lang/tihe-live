import {
  createCipheriv,
  createDecipheriv,
  createPrivateKey,
  createPublicKey,
  diffieHellman,
  generateKeyPairSync,
  hkdfSync,
  randomBytes,
} from 'node:crypto';

/**
 * Server half of the device key-wrapping scheme.
 *
 * ⚠️ **This must stay byte-compatible with `packages/secure-core/src/crypto.rs`.** The server
 * wraps; the Rust core on the device unwraps. A mismatch here does not fail a test — it produces
 * downloads that no device can open, and the cause is invisible from either side alone. The
 * fixture test in `key-wrap.test.ts` and the Rust-side vector in
 * `packages/secure-core/tests/wire_compat.rs` exist to catch exactly that.
 *
 * Wire format: `ephemeral_public(32) || nonce(12) || ciphertext+tag`
 *
 * Derivation, matching `derive_wrap_key` in the Rust:
 *   salt = ephemeral_public || device_public
 *   ikm  = X25519(ephemeral_private, device_public)
 *   info = "tihe-key-wrap-v1"
 *   key  = HKDF-SHA256(ikm, salt, info, 32)
 *
 * AAD is the device id, which binds a wrap to one device row: a wrapped key lifted from one
 * download manifest and replayed in another's fails to open even on the right hardware.
 */

const WRAP_INFO = Buffer.from('tihe-key-wrap-v1');
const NONCE_LEN = 12;
const TAG_LEN = 16;
const X25519_LEN = 32;

/** DER prefix for an X25519 raw public key, so 32 raw bytes can be handed to node:crypto. */
const X25519_SPKI_PREFIX = Buffer.from('302a300506032b656e032100', 'hex');
/** DER prefix for an X25519 raw private key. */
const X25519_PKCS8_PREFIX = Buffer.from('302e020100300506032b656e04220420', 'hex');

export function x25519PublicKeyFromRaw(raw: Buffer) {
  if (raw.length !== X25519_LEN) {
    throw new Error(`X25519 public key must be ${X25519_LEN} bytes, got ${raw.length}`);
  }
  return createPublicKey({
    key: Buffer.concat([X25519_SPKI_PREFIX, raw]),
    format: 'der',
    type: 'spki',
  });
}

export function x25519PrivateKeyFromRaw(raw: Buffer) {
  if (raw.length !== X25519_LEN) {
    throw new Error(`X25519 private key must be ${X25519_LEN} bytes, got ${raw.length}`);
  }
  return createPrivateKey({
    key: Buffer.concat([X25519_PKCS8_PREFIX, raw]),
    format: 'der',
    type: 'pkcs8',
  });
}

function deriveWrapKey(shared: Buffer, ephemeralPublic: Buffer, devicePublic: Buffer): Buffer {
  const salt = Buffer.concat([ephemeralPublic, devicePublic]);
  return Buffer.from(hkdfSync('sha256', shared, salt, WRAP_INFO, 32));
}

/**
 * Seals a content key so only the holder of `devicePublicKey`'s private half can open it.
 *
 * @param contentKey the 16-byte CEK
 * @param devicePublicKey the device's raw 32-byte X25519 public key
 * @param deviceId bound as AAD
 */
export function wrapKeyForDevice(
  contentKey: Buffer,
  devicePublicKey: Buffer,
  deviceId: string,
): Buffer {
  if (contentKey.length !== 16) {
    throw new Error(`content key must be 16 bytes, got ${contentKey.length}`);
  }

  // An ephemeral keypair per wrap: reusing one would let two wraps share a derived key.
  const ephemeral = generateKeyPairSync('x25519');
  const ephemeralPublicRaw = ephemeral.publicKey
    .export({ format: 'der', type: 'spki' })
    .subarray(X25519_SPKI_PREFIX.length);

  const shared = diffieHellman({
    privateKey: ephemeral.privateKey,
    publicKey: x25519PublicKeyFromRaw(devicePublicKey),
  });

  const aeadKey = deriveWrapKey(shared, ephemeralPublicRaw, devicePublicKey);
  const nonce = randomBytes(NONCE_LEN);

  const cipher = createCipheriv('chacha20-poly1305', aeadKey, nonce, { authTagLength: TAG_LEN });
  cipher.setAAD(Buffer.from(deviceId, 'utf8'), { plaintextLength: contentKey.length });
  const ciphertext = Buffer.concat([cipher.update(contentKey), cipher.final()]);
  const tag = cipher.getAuthTag();

  aeadKey.fill(0);
  shared.fill(0);

  return Buffer.concat([ephemeralPublicRaw, nonce, ciphertext, tag]);
}

/**
 * The client side, implemented here only so the round trip is testable in this repo without a
 * device. Production never calls this: the real unwrap happens in Rust on the device, using a
 * private key the server has never seen.
 */
export function unwrapKeyForDevice(
  wrapped: Buffer,
  devicePrivateKeyRaw: Buffer,
  deviceId: string,
): Buffer {
  if (wrapped.length < X25519_LEN + NONCE_LEN + TAG_LEN) {
    throw new Error('wrapped key is too short');
  }

  const ephemeralPublicRaw = wrapped.subarray(0, X25519_LEN);
  const nonce = wrapped.subarray(X25519_LEN, X25519_LEN + NONCE_LEN);
  const body = wrapped.subarray(X25519_LEN + NONCE_LEN);
  const ciphertext = body.subarray(0, body.length - TAG_LEN);
  const tag = body.subarray(body.length - TAG_LEN);

  const privateKey = x25519PrivateKeyFromRaw(devicePrivateKeyRaw);
  const devicePublicRaw = createPublicKey(privateKey)
    .export({ format: 'der', type: 'spki' })
    .subarray(X25519_SPKI_PREFIX.length);

  const shared = diffieHellman({
    privateKey,
    publicKey: x25519PublicKeyFromRaw(Buffer.from(ephemeralPublicRaw)),
  });

  const aeadKey = deriveWrapKey(
    shared,
    Buffer.from(ephemeralPublicRaw),
    Buffer.from(devicePublicRaw),
  );

  const decipher = createDecipheriv('chacha20-poly1305', aeadKey, nonce, {
    authTagLength: TAG_LEN,
  });
  decipher.setAAD(Buffer.from(deviceId, 'utf8'), { plaintextLength: ciphertext.length });
  decipher.setAuthTag(tag);

  const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);

  aeadKey.fill(0);
  shared.fill(0);

  return plaintext;
}

/**
 * Derives a segment IV from the key id and sequence number, matching `segment_iv` in the Rust.
 *
 * AES-CTR catastrophically leaks the XOR of two segments encrypted under the same (key, IV), so
 * uniqueness per segment is not optional. Deriving rather than storing keeps 16 bytes per segment
 * out of the database and guarantees both sides agree without extra metadata.
 */
export function segmentIv(keyId: string, sequence: number | bigint): Buffer {
  const seq = Buffer.alloc(8);
  seq.writeBigUInt64BE(BigInt(sequence));
  // Argument order matches the Rust exactly: IKM is the domain string, salt is the key id, and
  // info is the big-endian sequence number. Swapping IKM and info here produces plausible-looking
  // IVs that simply do not match the client's — which is unplayable video, not a test failure.
  return Buffer.from(
    hkdfSync('sha256', Buffer.from('tihe-segment-iv-v1'), Buffer.from(keyId, 'utf8'), seq, 16),
  );
}

/** Generates a fresh 128-bit content key. */
export function generateContentKey(): Buffer {
  return randomBytes(16);
}
