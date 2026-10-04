//! Platform key sealing.
//!
//! The device's X25519 private key must be stored so that it cannot be read off the disk or
//! copied to another machine. Each platform provides that differently:
//!
//! | Platform | Mechanism |
//! |---|---|
//! | Android | Android Keystore — key material held by the TEE/StrongBox where available |
//! | Windows | DPAPI (`CryptProtectData`), TPM-backed where available |
//! | iOS | Keychain with `kSecAttrTokenIDSecureEnclave` (M7) |
//!
//! Those implementations live behind platform channels in the Flutter layer, because they need
//! the OS SDKs. This module defines the trait they satisfy, plus a development fallback so the
//! crate builds and tests on Linux CI where no such facility exists.

use crate::error::Result;

/// Seals and unseals small secrets. The implementation decides where the sealing key lives; the
/// contract is that sealed bytes are useless on another device.
pub trait SecureStore: Send + Sync {
    fn seal(&self, label: &str, plaintext: &[u8]) -> Result<Vec<u8>>;
    fn unseal(&self, label: &str, sealed: &[u8]) -> Result<Vec<u8>>;
    /// True when sealing is backed by hardware. Reported to the server so the institute can see
    /// which devices hold keys in software only.
    fn is_hardware_backed(&self) -> bool;
}

/// Development-only store. Obfuscates rather than protects.
///
/// **Never ship this.** It exists so `cargo test` runs on a Linux CI machine with no keystore.
/// `is_hardware_backed()` returns false, and release builds assert on that: see
/// `assert_production_store`.
pub struct InsecureDevStore {
    obfuscation_key: [u8; 32],
}

impl InsecureDevStore {
    pub fn new() -> Self {
        // A fixed key, on purpose: a random one would make the "sealed" blobs unreadable across
        // test runs, and pretending otherwise would suggest this offers real protection.
        Self {
            obfuscation_key: *b"tihe-dev-store-NOT-production!!!",
        }
    }
}

impl Default for InsecureDevStore {
    fn default() -> Self {
        Self::new()
    }
}

impl SecureStore for InsecureDevStore {
    fn seal(&self, label: &str, plaintext: &[u8]) -> Result<Vec<u8>> {
        Ok(xor_with_label(&self.obfuscation_key, label, plaintext))
    }

    fn unseal(&self, label: &str, sealed: &[u8]) -> Result<Vec<u8>> {
        Ok(xor_with_label(&self.obfuscation_key, label, sealed))
    }

    fn is_hardware_backed(&self) -> bool {
        false
    }
}

fn xor_with_label(key: &[u8; 32], label: &str, data: &[u8]) -> Vec<u8> {
    let label_bytes = label.as_bytes();
    data.iter()
        .enumerate()
        .map(|(i, b)| {
            let k = key[i % key.len()];
            let l = if label_bytes.is_empty() {
                0
            } else {
                label_bytes[i % label_bytes.len()]
            };
            b ^ k ^ l
        })
        .collect()
}

/// Refuses to run a release build against a software-only store.
///
/// This is a tripwire, not a feature: shipping the dev store would silently reduce offline
/// protection to nothing, and that failure would be invisible in testing.
pub fn assert_production_store(store: &dyn SecureStore) -> Result<()> {
    #[cfg(not(debug_assertions))]
    if !store.is_hardware_backed() {
        return Err(crate::error::CoreError::Crypto);
    }
    let _ = store;
    Ok(())
}

/// Labels used with the store. Centralised so two call sites cannot disagree about a key's name
/// and silently create a second, empty one.
pub mod labels {
    pub const DEVICE_SECRET: &str = "tihe.device.x25519";
    pub const TIME_GUARD: &str = "tihe.timeguard";
    pub const LICENSE: &str = "tihe.license";
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::DeviceKeypair;

    #[test]
    fn sealing_round_trips() {
        let store = InsecureDevStore::new();
        let secret = b"a device private key would go here";

        let sealed = store.seal(labels::DEVICE_SECRET, secret).unwrap();
        let opened = store.unseal(labels::DEVICE_SECRET, &sealed).unwrap();

        assert_eq!(&opened, secret);
    }

    #[test]
    fn sealed_bytes_differ_from_plaintext() {
        let store = InsecureDevStore::new();
        let secret = b"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        let sealed = store.seal(labels::DEVICE_SECRET, secret).unwrap();
        assert_ne!(sealed.as_slice(), secret.as_slice());
    }

    #[test]
    fn the_wrong_label_does_not_recover_the_secret() {
        // Labels are domain separation: the time guard must not be readable as the device key.
        let store = InsecureDevStore::new();
        let secret = b"a device private key would go here";

        let sealed = store.seal(labels::DEVICE_SECRET, secret).unwrap();
        let opened = store.unseal(labels::TIME_GUARD, &sealed).unwrap();

        assert_ne!(&opened, secret);
    }

    #[test]
    fn a_device_keypair_survives_a_seal_unseal_cycle() {
        let store = InsecureDevStore::new();
        let original = DeviceKeypair::generate();

        let sealed = store
            .seal(labels::DEVICE_SECRET, &original.secret_bytes())
            .unwrap();
        let opened = store.unseal(labels::DEVICE_SECRET, &sealed).unwrap();

        let restored = DeviceKeypair::from_secret_bytes(opened.try_into().unwrap());
        assert_eq!(original.public_bytes(), restored.public_bytes());
    }

    #[test]
    fn the_dev_store_declares_itself_software_only() {
        // If this ever returns true, the production tripwire stops working.
        assert!(!InsecureDevStore::new().is_hardware_backed());
    }
}
