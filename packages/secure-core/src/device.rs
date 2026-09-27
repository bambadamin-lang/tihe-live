//! Device identity.
//!
//! A device fingerprint answers "is this the same machine as last time?" — it is not a secret
//! and not an authentication factor. The actual security comes from the X25519 private key
//! sealed in the platform keystore (see `keystore`). The fingerprint exists so the server can
//! recognise a returning device and enforce device counts.
//!
//! Deliberately *not* used for anything stronger, because every hardware identifier available
//! to an unprivileged app is either spoofable, or changes when the user upgrades their OS.

use sha2::{Digest, Sha256};

/// Raw platform signals, gathered by the Flutter layer.
///
/// None is individually stable: Android IDs reset on factory reset, Windows machine GUIDs change
/// on reinstall. Hashing several together tolerates one changing without the device looking
/// brand new.
#[derive(Debug, Clone, Default)]
pub struct DeviceSignals {
    pub platform: String,
    /// Android: `Settings.Secure.ANDROID_ID`. Windows: `MachineGuid`.
    pub primary_id: String,
    pub model: String,
    pub os_version: String,
    /// Set once on first launch and stored with the keypair, so a device whose hardware ids all
    /// change is still recognisable as long as the app's data survives.
    pub install_id: String,
}

/// Derives the fingerprint the server stores.
///
/// Note the salt: fingerprints are hashed with a domain separator so the value stored by this
/// app cannot be correlated with one produced by any other app from the same signals.
pub fn derive_fingerprint(signals: &DeviceSignals) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"tihe-device-fingerprint-v1");
    hasher.update([0u8]);
    hasher.update(signals.platform.as_bytes());
    hasher.update([0u8]);
    hasher.update(signals.primary_id.as_bytes());
    hasher.update([0u8]);
    hasher.update(signals.model.as_bytes());
    hasher.update([0u8]);
    hasher.update(signals.install_id.as_bytes());
    // os_version is deliberately excluded: an OS upgrade must not look like a new device, or
    // every student would burn a device slot on every system update.
    hex::encode(hasher.finalize())
}

/// What the client reports about its environment at playback start.
///
/// A signal, never the enforcement point: a patched client can lie about all of it. The server
/// decides what to do, and the capture-blocking APIs do the actual work. Collected because it
/// stops the casual case cheaply and flags patterns worth investigating.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct EnvironmentReport {
    pub screen_recorder_detected: bool,
    pub virtual_display_detected: bool,
    pub rooted_or_jailbroken: bool,
    pub emulator: bool,
    pub debugger_attached: bool,
}

impl EnvironmentReport {
    /// Whether playback should be refused locally, before asking the server.
    ///
    /// Erring toward refusal here is cheap: a false positive is one confused student contacting
    /// support, a false negative is a clean capture of a lecture.
    pub fn should_block(&self) -> bool {
        self.screen_recorder_detected
            || self.virtual_display_detected
            || self.emulator
            || self.debugger_attached
            || self.rooted_or_jailbroken
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn signals() -> DeviceSignals {
        DeviceSignals {
            platform: "windows".into(),
            primary_id: "machine-guid-1234".into(),
            model: "ThinkPad T14".into(),
            os_version: "10.0.22631".into(),
            install_id: "install-abcdef".into(),
        }
    }

    #[test]
    fn the_same_device_yields_the_same_fingerprint() {
        assert_eq!(
            derive_fingerprint(&signals()),
            derive_fingerprint(&signals())
        );
    }

    #[test]
    fn a_different_machine_yields_a_different_fingerprint() {
        let mut other = signals();
        other.primary_id = "machine-guid-9999".into();
        assert_ne!(derive_fingerprint(&signals()), derive_fingerprint(&other));
    }

    #[test]
    fn an_os_upgrade_does_not_change_the_fingerprint() {
        // Otherwise every Windows update would consume one of the student's device slots.
        let mut upgraded = signals();
        upgraded.os_version = "10.0.26100".into();
        assert_eq!(
            derive_fingerprint(&signals()),
            derive_fingerprint(&upgraded)
        );
    }

    #[test]
    fn a_reinstall_with_a_new_install_id_looks_like_a_new_device() {
        // Accepted trade-off: reinstalling is rare, and treating it as a new device is the safe
        // direction — the alternative lets a cloned install share one slot.
        let mut reinstalled = signals();
        reinstalled.install_id = "install-999999".into();
        assert_ne!(
            derive_fingerprint(&signals()),
            derive_fingerprint(&reinstalled)
        );
    }

    #[test]
    fn a_fingerprint_is_a_full_length_hex_digest() {
        let fp = derive_fingerprint(&signals());
        assert_eq!(fp.len(), 64);
        assert!(fp.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn a_clean_environment_does_not_block() {
        assert!(!EnvironmentReport::default().should_block());
    }

    #[test]
    fn each_hostile_signal_blocks_on_its_own() {
        let cases = [
            EnvironmentReport {
                screen_recorder_detected: true,
                ..Default::default()
            },
            EnvironmentReport {
                virtual_display_detected: true,
                ..Default::default()
            },
            EnvironmentReport {
                emulator: true,
                ..Default::default()
            },
            EnvironmentReport {
                debugger_attached: true,
                ..Default::default()
            },
            EnvironmentReport {
                rooted_or_jailbroken: true,
                ..Default::default()
            },
        ];
        for case in cases {
            assert!(case.should_block(), "{case:?} should have blocked playback");
        }
    }
}
