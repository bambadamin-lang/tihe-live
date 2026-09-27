//! Symmetric and asymmetric primitives.
//!
//! Two jobs: decrypt media segments fast, and move a content key from the server to exactly one
//! device. Nothing here decides *whether* a key should be handed over — that is `license`.

use aes::cipher::{KeyIvInit, StreamCipher};
use chacha20poly1305::{
    aead::{Aead, KeyInit, Payload},
    ChaCha20Poly1305, Nonce,
};
use hkdf::Hkdf;
use rand::RngCore;
use sha2::Sha256;
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::error::{CoreError, Result};

type Aes128Ctr = ctr::Ctr128BE<aes::Aes128>;

pub const CEK_LEN: usize = 16;
pub const IV_LEN: usize = 16;

/// A content encryption key, zeroed when dropped.
///
/// The `ZeroizeOnDrop` is not decoration: a CEK left in freed memory after playback ends
/// undoes the reason this crate exists. Debug is implemented manually so a stray `{:?}` in a
/// log statement cannot print the key.
#[derive(Clone, ZeroizeOnDrop)]
pub struct ContentKey([u8; CEK_LEN]);

impl ContentKey {
    pub fn from_bytes(bytes: [u8; CEK_LEN]) -> Self {
        Self(bytes)
    }

    pub fn from_slice(bytes: &[u8]) -> Result<Self> {
        if bytes.len() != CEK_LEN {
            return Err(CoreError::Crypto);
        }
        let mut k = [0u8; CEK_LEN];
        k.copy_from_slice(bytes);
        Ok(Self(k))
    }

    pub fn random() -> Self {
        let mut k = [0u8; CEK_LEN];
        rand::thread_rng().fill_bytes(&mut k);
        Self(k)
    }

    fn as_bytes(&self) -> &[u8; CEK_LEN] {
        &self.0
    }
}

impl std::fmt::Debug for ContentKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Never print key material, not even truncated.
        f.write_str("ContentKey(redacted)")
    }
}

/// Derives a segment's IV from the sequence number.
///
/// AES-CTR reuses of an (key, IV) pair are catastrophic — two segments encrypted under the same
/// counter stream leak their XOR. Deriving the IV from the segment sequence guarantees
/// uniqueness within a video without storing 16 bytes per segment, and the derivation is
/// reproducible so the server and client agree without extra metadata.
pub fn segment_iv(key_id: &str, sequence: u64) -> [u8; IV_LEN] {
    let hk = Hkdf::<Sha256>::new(Some(key_id.as_bytes()), b"tihe-segment-iv-v1");
    let mut iv = [0u8; IV_LEN];
    // Expansion cannot fail for a 16-byte output.
    hk.expand(&sequence.to_be_bytes(), &mut iv)
        .expect("HKDF expand of 16 bytes cannot fail");
    iv
}

/// Encrypts or decrypts a segment in place. AES-CTR is symmetric, so this is one function.
pub fn apply_segment_cipher(key: &ContentKey, iv: &[u8; IV_LEN], data: &mut [u8]) {
    let mut cipher = Aes128Ctr::new(key.as_bytes().into(), iv.into());
    cipher.apply_keystream(data);
}

/// A device's X25519 keypair. The secret half is sealed by the platform keystore and never
/// leaves the device; only the public half is sent to the server.
#[derive(ZeroizeOnDrop)]
pub struct DeviceKeypair {
    #[zeroize(skip)]
    public: PublicKey,
    secret: StaticSecret,
}

impl DeviceKeypair {
    pub fn generate() -> Self {
        let secret = StaticSecret::random_from_rng(rand::thread_rng());
        let public = PublicKey::from(&secret);
        Self { public, secret }
    }

    pub fn from_secret_bytes(bytes: [u8; 32]) -> Self {
        let secret = StaticSecret::from(bytes);
        let public = PublicKey::from(&secret);
        Self { public, secret }
    }

    pub fn public_bytes(&self) -> [u8; 32] {
        self.public.to_bytes()
    }

    pub fn secret_bytes(&self) -> [u8; 32] {
        self.secret.to_bytes()
    }
}

impl std::fmt::Debug for DeviceKeypair {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("DeviceKeypair(public only)")
    }
}

/// Wraps a content key for one device: an ephemeral X25519 exchange feeding ChaCha20-Poly1305.
///
/// Layout: `ephemeral_public (32) || nonce (12) || ciphertext+tag`.
///
/// This is the server side of the exchange, implemented here so the round trip can be tested
/// without a server, and so the CLI can produce fixtures.
///
/// The AAD binds the wrap to a specific device id — a wrapped key lifted from one device's
/// download manifest and replayed in another's fails to open even if both keys were known.
pub fn wrap_key_for_device(
    key: &ContentKey,
    device_public: &[u8; 32],
    device_id: &str,
) -> Result<Vec<u8>> {
    let ephemeral = StaticSecret::random_from_rng(rand::thread_rng());
    let ephemeral_public = PublicKey::from(&ephemeral);
    let shared = ephemeral.diffie_hellman(&PublicKey::from(*device_public));

    let mut aead_key = derive_wrap_key(
        shared.as_bytes(),
        &ephemeral_public.to_bytes(),
        device_public,
    );
    let cipher = ChaCha20Poly1305::new((&aead_key).into());
    aead_key.zeroize();

    let mut nonce_bytes = [0u8; 12];
    rand::thread_rng().fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(
            nonce,
            Payload {
                msg: key.as_bytes(),
                aad: device_id.as_bytes(),
            },
        )
        .map_err(|_| CoreError::Crypto)?;

    let mut out = Vec::with_capacity(32 + 12 + ciphertext.len());
    out.extend_from_slice(&ephemeral_public.to_bytes());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

/// Unwraps a content key sealed to this device. The client side of the exchange.
pub fn unwrap_key_for_device(
    wrapped: &[u8],
    keypair: &DeviceKeypair,
    device_id: &str,
) -> Result<ContentKey> {
    if wrapped.len() < 32 + 12 + CEK_LEN {
        return Err(CoreError::KeyUnwrap);
    }
    let mut ephemeral_public = [0u8; 32];
    ephemeral_public.copy_from_slice(&wrapped[..32]);
    let nonce_bytes = &wrapped[32..44];
    let ciphertext = &wrapped[44..];

    let shared = keypair
        .secret
        .diffie_hellman(&PublicKey::from(ephemeral_public));

    let device_public = keypair.public_bytes();
    let mut aead_key = derive_wrap_key(shared.as_bytes(), &ephemeral_public, &device_public);
    let cipher = ChaCha20Poly1305::new((&aead_key).into());
    aead_key.zeroize();

    let mut plaintext = cipher
        .decrypt(
            Nonce::from_slice(nonce_bytes),
            Payload {
                msg: ciphertext,
                aad: device_id.as_bytes(),
            },
        )
        .map_err(|_| CoreError::KeyUnwrap)?;

    let key = ContentKey::from_slice(&plaintext)?;
    plaintext.zeroize();
    Ok(key)
}

/// Binds the derived AEAD key to both public keys, so a shared secret alone is not enough to
/// produce a valid wrap.
fn derive_wrap_key(
    shared: &[u8],
    ephemeral_public: &[u8; 32],
    device_public: &[u8; 32],
) -> [u8; 32] {
    let mut salt = Vec::with_capacity(64);
    salt.extend_from_slice(ephemeral_public);
    salt.extend_from_slice(device_public);
    let hk = Hkdf::<Sha256>::new(Some(&salt), shared);
    let mut out = [0u8; 32];
    hk.expand(b"tihe-key-wrap-v1", &mut out)
        .expect("HKDF expand of 32 bytes cannot fail");
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn segment_cipher_round_trips() {
        let key = ContentKey::random();
        let iv = segment_iv("ck_test", 7);
        let original = b"a fragment of an encrypted lecture".to_vec();

        let mut buf = original.clone();
        apply_segment_cipher(&key, &iv, &mut buf);
        assert_ne!(buf, original, "ciphertext must differ from plaintext");

        apply_segment_cipher(&key, &iv, &mut buf);
        assert_eq!(buf, original);
    }

    #[test]
    fn segment_ivs_are_unique_per_sequence() {
        // AES-CTR IV reuse leaks the XOR of two segments, so this property is load-bearing.
        let a = segment_iv("ck_test", 1);
        let b = segment_iv("ck_test", 2);
        assert_ne!(a, b);
    }

    #[test]
    fn segment_ivs_differ_across_videos() {
        // Two videos at the same sequence number must not share an IV either.
        let a = segment_iv("ck_one", 1);
        let b = segment_iv("ck_two", 1);
        assert_ne!(a, b);
    }

    #[test]
    fn segment_iv_is_reproducible() {
        // Server and client derive independently; they must agree.
        assert_eq!(segment_iv("ck_test", 42), segment_iv("ck_test", 42));
    }

    #[test]
    fn wrong_key_does_not_recover_plaintext() {
        let key = ContentKey::random();
        let other = ContentKey::random();
        let iv = segment_iv("ck_test", 0);
        let original = b"lecture bytes".to_vec();

        let mut buf = original.clone();
        apply_segment_cipher(&key, &iv, &mut buf);
        apply_segment_cipher(&other, &iv, &mut buf);
        assert_ne!(buf, original);
    }

    #[test]
    fn key_wrap_round_trips_for_the_right_device() {
        let device = DeviceKeypair::generate();
        let key = ContentKey::random();
        let device_id = "dev_01J8ZQK5T9XVWR3M2N4P6H8B7C";

        let wrapped = wrap_key_for_device(&key, &device.public_bytes(), device_id).unwrap();
        let unwrapped = unwrap_key_for_device(&wrapped, &device, device_id).unwrap();

        assert_eq!(unwrapped.as_bytes(), key.as_bytes());
    }

    #[test]
    fn key_wrap_fails_on_a_different_device() {
        // This is the property that makes a copied .tihex file useless: the wrapped key cannot
        // be opened without the private half that never left the original device.
        let alice = DeviceKeypair::generate();
        let bob = DeviceKeypair::generate();
        let key = ContentKey::random();

        let wrapped = wrap_key_for_device(&key, &alice.public_bytes(), "dev_alice").unwrap();

        assert!(matches!(
            unwrap_key_for_device(&wrapped, &bob, "dev_alice"),
            Err(CoreError::KeyUnwrap)
        ));
    }

    #[test]
    fn key_wrap_fails_when_the_device_id_is_swapped() {
        // The device id is AAD, so replaying a wrap under a different id fails even on the
        // correct device.
        let device = DeviceKeypair::generate();
        let key = ContentKey::random();
        let wrapped = wrap_key_for_device(&key, &device.public_bytes(), "dev_real").unwrap();

        assert!(unwrap_key_for_device(&wrapped, &device, "dev_forged").is_err());
    }

    #[test]
    fn key_wrap_fails_on_tampered_ciphertext() {
        let device = DeviceKeypair::generate();
        let key = ContentKey::random();
        let mut wrapped = wrap_key_for_device(&key, &device.public_bytes(), "dev_x").unwrap();

        let last = wrapped.len() - 1;
        wrapped[last] ^= 0xff;

        assert!(unwrap_key_for_device(&wrapped, &device, "dev_x").is_err());
    }

    #[test]
    fn debug_never_prints_key_material() {
        let key = ContentKey::from_bytes([0xab; CEK_LEN]);
        let printed = format!("{key:?}");
        assert!(!printed.contains("ab"));
        assert!(printed.contains("redacted"));
    }

    #[test]
    fn keypair_from_secret_bytes_reproduces_public_half() {
        let original = DeviceKeypair::generate();
        let restored = DeviceKeypair::from_secret_bytes(original.secret_bytes());
        assert_eq!(original.public_bytes(), restored.public_bytes());
    }
}
