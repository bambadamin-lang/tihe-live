//! # secure-core
//!
//! Content protection for TIHE Live. Every secret in this product is handled here and nowhere
//! else — not in Dart, not in the video engine, not on disk in plaintext.
//!
//! **Read `docs/03-content-protection.md` before changing anything in this crate.** The design
//! constraints are not obvious from the code, and several look like over-engineering until you
//! know which attack they answer.
//!
//! ## Layout
//!
//! * [`crypto`] — AES-128-CTR segments, X25519 key wrapping, IV derivation
//! * [`license`] — Ed25519 licence verification, expiry, clock-rollback defence
//! * [`device`] — fingerprints and environment reports
//! * [`container`] — the `.tihex` offline container
//! * [`keystore`] — platform key sealing, with a development fallback
//! * [`loopback`] — access policy for the local HLS server
//!
//! ## What this crate will not do
//!
//! It holds no signing key and cannot mint a licence or sign a container header. Those are
//! server powers. If a change here seems to need one, the design has gone wrong.

pub mod container;
pub mod crypto;
pub mod device;
pub mod error;
pub mod keystore;
pub mod license;
pub mod loopback;

pub use error::{CoreError, Result};

/// Crate version, reported to the server so the institute can see which protection build a
/// device is running — useful when a vulnerability needs a forced upgrade.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Runs the protection primitives end to end and reports what passed.
///
/// Its purpose is cross-compilation confidence: a build that links for Android or Windows can
/// still fail at runtime on a missing RNG or an unavailable keystore. Calling this once at
/// startup turns that into an immediate, legible failure instead of a decryption error later.
pub fn self_test() -> Result<Vec<String>> {
    use crypto::{
        apply_segment_cipher, segment_iv, unwrap_key_for_device, wrap_key_for_device, ContentKey,
        DeviceKeypair,
    };

    let mut checks = Vec::new();

    let key = ContentKey::random();
    checks.push("csprng available".to_string());

    let iv = segment_iv("ck_selftest", 1);
    let original = b"self test payload".to_vec();
    let mut buf = original.clone();
    apply_segment_cipher(&key, &iv, &mut buf);
    if buf == original {
        return Err(CoreError::Crypto);
    }
    apply_segment_cipher(&key, &iv, &mut buf);
    if buf != original {
        return Err(CoreError::Crypto);
    }
    checks.push("AES-128-CTR round trip".to_string());

    let device = DeviceKeypair::generate();
    let wrapped = wrap_key_for_device(&key, &device.public_bytes(), "dev_selftest")?;
    unwrap_key_for_device(&wrapped, &device, "dev_selftest")?;
    checks.push("X25519 key wrap round trip".to_string());

    // A wrap must not open on a different device. If this ever passes, offline protection is
    // broken and the build must not ship.
    let other = DeviceKeypair::generate();
    if unwrap_key_for_device(&wrapped, &other, "dev_selftest").is_ok() {
        return Err(CoreError::Crypto);
    }
    checks.push("key wrap rejects a foreign device".to_string());

    Ok(checks)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn self_test_passes_and_reports_every_check() {
        let checks = self_test().expect("self test must pass on a supported platform");
        assert_eq!(checks.len(), 4);
    }
}
