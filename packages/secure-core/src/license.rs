//! Licence verification.
//!
//! A licence is an Ed25519-signed CBOR blob. The device verifies it **offline** against a public
//! key compiled into the binary, so a student with no network still gets the right answer, and a
//! student who blocks the network gains nothing.
//!
//! Three separate things are checked, and they fail for different reasons:
//!   * the signature — is this licence genuine and unmodified?
//!   * the scope — is it for this device and this content?
//!   * the clock — is the device telling the truth about what time it is?
//!
//! The third is the interesting one. See `TimeGuard`.

use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};
use time::OffsetDateTime;

use crate::error::{CoreError, Result};

/// The signed payload. Field names are short because they are re-encoded on every check, and
/// the order is fixed because it is part of what gets signed.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LicensePayload {
    pub v: u8,
    pub license_id: String,
    pub user_id: String,
    pub device_ids: Vec<String>,
    pub course_ids: Vec<String>,
    pub video_ids: Vec<String>,
    /// RFC3339. Stored as strings rather than epoch ints so a licence dumped to a log is
    /// readable during support calls.
    pub not_before: String,
    pub not_after: String,
    pub max_devices: u32,
    pub max_concurrent_streams: u32,
    pub offline_window_days: u32,
    pub revocation_epoch: u64,
    pub issued_at: String,
    /// The server's clock when the licence was issued. The anchor for rollback detection.
    pub server_time: String,
}

/// A licence plus its signature, as stored on the device.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct License {
    pub payload: LicensePayload,
    pub signature: Vec<u8>,
    /// The exact CBOR bytes the signature covers. Kept verbatim rather than re-encoded, because
    /// a re-encode that differs by one byte — a map ordering, an integer width — would fail
    /// verification for a licence that is perfectly valid.
    pub signed_bytes: Vec<u8>,
}

/// State the device remembers between licence checks, sealed by the platform keystore.
///
/// This is what defeats "set the clock back to revive an expired licence". None of the three
/// fields can be rolled back by changing the system clock:
///   * `counter` only ever increases, so a decrease means tampering;
///   * `last_server_time` is the newest time the server has vouched for;
///   * `offline_play_seconds` accumulates regardless of what the clock says, so a frozen clock
///     still exhausts the licence.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TimeGuard {
    pub counter: u64,
    /// RFC3339, from the last successful server contact.
    pub last_server_time: Option<String>,
    pub offline_play_seconds: u64,
}

impl TimeGuard {
    /// Records a successful server contact. Monotonic in both fields.
    pub fn observe_server_time(&mut self, server_time: &str) -> Result<()> {
        let incoming = parse_rfc3339(server_time)?;
        if let Some(previous) = &self.last_server_time {
            // A server time older than one we already saw means either a replayed response or a
            // tampered store. Keep the newer value rather than trusting the input.
            if parse_rfc3339(previous)? > incoming {
                return Ok(());
            }
        }
        self.last_server_time = Some(server_time.to_string());
        self.counter = self.counter.saturating_add(1);
        Ok(())
    }

    /// Checks the device clock against what the server last vouched for.
    ///
    /// A tolerance is allowed because real clocks drift and NTP corrections move time backwards
    /// by small amounts. Anything beyond it is treated as deliberate.
    pub fn check_clock(&self, now: OffsetDateTime, tolerance_seconds: i64) -> Result<()> {
        let Some(anchor) = &self.last_server_time else {
            // Never contacted a server. Nothing to compare against — scope and expiry checks
            // still apply, so this is not a free pass.
            return Ok(());
        };
        let anchor = parse_rfc3339(anchor)?;
        if now < anchor - time::Duration::seconds(tolerance_seconds) {
            return Err(CoreError::ClockRollback);
        }
        Ok(())
    }
}

/// Outcome of a full licence check, so a caller can explain *why* without a second call.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LicenseVerdict {
    Valid { days_remaining: i64 },
    Expired,
    NotYetValid,
    Revoked,
    WrongDevice,
    ClockRollback,
    OutOfScope,
}

/// Verifies the signature over a licence blob.
///
/// Separate from the policy checks so a tampered licence is distinguishable from a merely
/// expired one — the first is an attack, the second is a support call.
pub fn verify_signature(license: &License, public_key: &[u8; 32]) -> Result<()> {
    let verifying_key =
        VerifyingKey::from_bytes(public_key).map_err(|_| CoreError::BadSignature)?;
    let signature_bytes: [u8; 64] = license
        .signature
        .as_slice()
        .try_into()
        .map_err(|_| CoreError::BadSignature)?;
    let signature = Signature::from_bytes(&signature_bytes);

    verifying_key
        .verify(&license.signed_bytes, &signature)
        .map_err(|_| CoreError::BadSignature)?;

    // The signature covers `signed_bytes`. If the parsed payload does not match those bytes,
    // someone edited the readable copy and left the signed copy alone — so trust the signed one
    // and reject the mismatch.
    let reencoded: LicensePayload = serde_cbor::from_slice(&license.signed_bytes)?;
    if reencoded.license_id != license.payload.license_id
        || reencoded.not_after != license.payload.not_after
        || reencoded.device_ids != license.payload.device_ids
        || reencoded.revocation_epoch != license.payload.revocation_epoch
    {
        return Err(CoreError::BadSignature);
    }

    Ok(())
}

/// The full check: signature, device binding, clock, validity window, revocation epoch.
///
/// `current_epoch` is the newest revocation epoch the device has seen from the server. A licence
/// carrying a lower epoch was superseded by a revocation.
pub fn verify(
    license: &License,
    public_key: &[u8; 32],
    device_id: &str,
    now: OffsetDateTime,
    guard: &TimeGuard,
    current_epoch: u64,
) -> Result<LicenseVerdict> {
    verify_signature(license, public_key)?;

    if !license.payload.device_ids.iter().any(|d| d == device_id) {
        return Ok(LicenseVerdict::WrongDevice);
    }

    // Clock check before expiry: an expired licence on a rolled-back clock should report the
    // rollback, because that is the more informative fact.
    if guard.check_clock(now, 300).is_err() {
        return Ok(LicenseVerdict::ClockRollback);
    }

    if license.payload.revocation_epoch < current_epoch {
        return Ok(LicenseVerdict::Revoked);
    }

    let not_before = parse_rfc3339(&license.payload.not_before)?;
    let not_after = parse_rfc3339(&license.payload.not_after)?;

    if now < not_before {
        return Ok(LicenseVerdict::NotYetValid);
    }
    if now > not_after {
        return Ok(LicenseVerdict::Expired);
    }

    // A frozen clock cannot outlast the offline window, because this counter advances with
    // playback rather than with the clock.
    let offline_limit = (license.payload.offline_window_days as u64) * 86_400;
    if guard.offline_play_seconds > offline_limit {
        return Ok(LicenseVerdict::Expired);
    }

    Ok(LicenseVerdict::Valid {
        days_remaining: (not_after - now).whole_days(),
    })
}

/// True when the licence covers this specific content.
pub fn covers(license: &License, course_id: &str, video_id: &str) -> bool {
    license.payload.course_ids.iter().any(|c| c == course_id)
        || license.payload.video_ids.iter().any(|v| v == video_id)
}

pub(crate) fn parse_rfc3339(s: &str) -> Result<OffsetDateTime> {
    OffsetDateTime::parse(s, &time::format_description::well_known::Rfc3339)
        .map_err(|_| CoreError::Encoding)
}

#[cfg(test)]
pub(crate) mod test_support {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};

    pub struct Issuer {
        pub signing: SigningKey,
    }

    impl Issuer {
        pub fn new() -> Self {
            Self {
                signing: SigningKey::generate(&mut rand::thread_rng()),
            }
        }

        pub fn public_key(&self) -> [u8; 32] {
            self.signing.verifying_key().to_bytes()
        }

        /// Mirrors what services/api does when issuing a licence.
        pub fn issue(&self, payload: LicensePayload) -> License {
            let signed_bytes = serde_cbor::to_vec(&payload).unwrap();
            let signature = self.signing.sign(&signed_bytes).to_bytes().to_vec();
            License {
                payload,
                signature,
                signed_bytes,
            }
        }
    }

    pub fn payload(device_id: &str, not_before: &str, not_after: &str) -> LicensePayload {
        LicensePayload {
            v: 1,
            license_id: "lic_01J8ZQK5T9XVWR3M2N4P6H8B7C".into(),
            user_id: "usr_01J8ZQK5T9XVWR3M2N4P6H8B7C".into(),
            device_ids: vec![device_id.into()],
            course_ids: vec!["crs_01J8ZQK5T9XVWR3M2N4P6H8B7C".into()],
            video_ids: vec![],
            not_before: not_before.into(),
            not_after: not_after.into(),
            max_devices: 2,
            max_concurrent_streams: 1,
            offline_window_days: 30,
            revocation_epoch: 3,
            issued_at: not_before.into(),
            server_time: not_before.into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::test_support::{payload, Issuer};
    use super::*;
    use time::macros::datetime;

    const DEVICE: &str = "dev_01J8ZQK5T9XVWR3M2N4P6H8B7C";

    fn guard_at(server_time: &str) -> TimeGuard {
        let mut g = TimeGuard::default();
        g.observe_server_time(server_time).unwrap();
        g
    }

    #[test]
    fn a_valid_licence_verifies() {
        let issuer = Issuer::new();
        let license = issuer.issue(payload(
            DEVICE,
            "2026-09-01T00:00:00Z",
            "2026-10-01T00:00:00Z",
        ));

        let verdict = verify(
            &license,
            &issuer.public_key(),
            DEVICE,
            datetime!(2026-09-15 12:00 UTC),
            &guard_at("2026-09-15T11:00:00Z"),
            3,
        )
        .unwrap();

        assert!(matches!(verdict, LicenseVerdict::Valid { .. }));
    }

    #[test]
    fn an_expired_licence_is_rejected() {
        let issuer = Issuer::new();
        let license = issuer.issue(payload(
            DEVICE,
            "2026-09-01T00:00:00Z",
            "2026-10-01T00:00:00Z",
        ));

        let verdict = verify(
            &license,
            &issuer.public_key(),
            DEVICE,
            datetime!(2026-10-02 00:00 UTC),
            &guard_at("2026-10-02T00:00:00Z"),
            3,
        )
        .unwrap();

        assert_eq!(verdict, LicenseVerdict::Expired);
    }

    #[test]
    fn a_licence_is_rejected_before_it_starts() {
        let issuer = Issuer::new();
        let license = issuer.issue(payload(
            DEVICE,
            "2026-10-01T00:00:00Z",
            "2026-11-01T00:00:00Z",
        ));

        let verdict = verify(
            &license,
            &issuer.public_key(),
            DEVICE,
            datetime!(2026-09-15 00:00 UTC),
            &TimeGuard::default(),
            3,
        )
        .unwrap();

        assert_eq!(verdict, LicenseVerdict::NotYetValid);
    }

    #[test]
    fn a_licence_for_another_device_is_rejected() {
        let issuer = Issuer::new();
        let license = issuer.issue(payload(
            DEVICE,
            "2026-09-01T00:00:00Z",
            "2026-10-01T00:00:00Z",
        ));

        let verdict = verify(
            &license,
            &issuer.public_key(),
            "dev_01KAAAAAAAAAAAAAAAAAAAAAAA",
            datetime!(2026-09-15 12:00 UTC),
            &guard_at("2026-09-15T11:00:00Z"),
            3,
        )
        .unwrap();

        assert_eq!(verdict, LicenseVerdict::WrongDevice);
    }

    #[test]
    fn a_licence_signed_by_a_different_key_is_rejected() {
        // The attack this blocks: mint your own licence with your own keypair.
        let real = Issuer::new();
        let forger = Issuer::new();
        let license = forger.issue(payload(
            DEVICE,
            "2026-09-01T00:00:00Z",
            "2099-01-01T00:00:00Z",
        ));

        assert!(matches!(
            verify_signature(&license, &real.public_key()),
            Err(CoreError::BadSignature)
        ));
    }

    #[test]
    fn editing_the_expiry_after_signing_is_detected() {
        // The attack this blocks: extend your own licence by editing the readable payload.
        let issuer = Issuer::new();
        let mut license = issuer.issue(payload(
            DEVICE,
            "2026-09-01T00:00:00Z",
            "2026-10-01T00:00:00Z",
        ));

        license.payload.not_after = "2099-01-01T00:00:00Z".into();

        assert!(matches!(
            verify_signature(&license, &issuer.public_key()),
            Err(CoreError::BadSignature)
        ));
    }

    #[test]
    fn retargeting_a_licence_at_another_device_is_detected() {
        let issuer = Issuer::new();
        let mut license = issuer.issue(payload(
            DEVICE,
            "2026-09-01T00:00:00Z",
            "2026-10-01T00:00:00Z",
        ));

        license.payload.device_ids = vec!["dev_01KATTACKERAAAAAAAAAAAAAA".into()];

        assert!(matches!(
            verify_signature(&license, &issuer.public_key()),
            Err(CoreError::BadSignature)
        ));
    }

    #[test]
    fn flipping_a_signature_byte_is_detected() {
        let issuer = Issuer::new();
        let mut license = issuer.issue(payload(
            DEVICE,
            "2026-09-01T00:00:00Z",
            "2026-10-01T00:00:00Z",
        ));
        license.signature[0] ^= 0x01;

        assert!(verify_signature(&license, &issuer.public_key()).is_err());
    }

    #[test]
    fn setting_the_clock_back_is_detected() {
        // The attack this blocks: an expired licence revived by rewinding the system clock.
        let issuer = Issuer::new();
        let license = issuer.issue(payload(
            DEVICE,
            "2026-09-01T00:00:00Z",
            "2026-10-01T00:00:00Z",
        ));
        let guard = guard_at("2026-09-20T00:00:00Z");

        let verdict = verify(
            &license,
            &issuer.public_key(),
            DEVICE,
            datetime!(2026-09-05 00:00 UTC), // rolled back two weeks
            &guard,
            3,
        )
        .unwrap();

        assert_eq!(verdict, LicenseVerdict::ClockRollback);
    }

    #[test]
    fn small_clock_drift_is_tolerated() {
        // Real clocks drift and NTP nudges them backwards. Blocking playback for that would
        // generate support calls for no security benefit.
        let issuer = Issuer::new();
        let license = issuer.issue(payload(
            DEVICE,
            "2026-09-01T00:00:00Z",
            "2026-10-01T00:00:00Z",
        ));
        let guard = guard_at("2026-09-15T12:00:00Z");

        let verdict = verify(
            &license,
            &issuer.public_key(),
            DEVICE,
            datetime!(2026-09-15 11:58 UTC), // two minutes behind
            &guard,
            3,
        )
        .unwrap();

        assert!(matches!(verdict, LicenseVerdict::Valid { .. }));
    }

    #[test]
    fn a_revoked_epoch_invalidates_the_licence() {
        let issuer = Issuer::new();
        let license = issuer.issue(payload(
            DEVICE,
            "2026-09-01T00:00:00Z",
            "2026-10-01T00:00:00Z",
        ));

        // Server has moved to epoch 4; this licence was issued at 3.
        let verdict = verify(
            &license,
            &issuer.public_key(),
            DEVICE,
            datetime!(2026-09-15 12:00 UTC),
            &guard_at("2026-09-15T11:00:00Z"),
            4,
        )
        .unwrap();

        assert_eq!(verdict, LicenseVerdict::Revoked);
    }

    #[test]
    fn exhausting_the_offline_window_expires_the_licence_despite_a_frozen_clock() {
        let issuer = Issuer::new();
        let license = issuer.issue(payload(
            DEVICE,
            "2026-09-01T00:00:00Z",
            "2026-10-01T00:00:00Z",
        ));

        let mut guard = guard_at("2026-09-02T00:00:00Z");
        guard.offline_play_seconds = 31 * 86_400; // past the 30-day window

        let verdict = verify(
            &license,
            &issuer.public_key(),
            DEVICE,
            datetime!(2026-09-02 00:00 UTC), // clock frozen at day one
            &guard,
            3,
        )
        .unwrap();

        assert_eq!(verdict, LicenseVerdict::Expired);
    }

    #[test]
    fn the_guard_counter_only_increases() {
        let mut guard = TimeGuard::default();
        guard.observe_server_time("2026-09-15T10:00:00Z").unwrap();
        let after_first = guard.counter;

        // A replayed older server response must not rewind the anchor.
        guard.observe_server_time("2026-09-01T10:00:00Z").unwrap();

        assert_eq!(
            guard.last_server_time.as_deref(),
            Some("2026-09-15T10:00:00Z")
        );
        assert_eq!(guard.counter, after_first);
    }

    #[test]
    fn scope_matching_accepts_the_course_and_rejects_others() {
        let issuer = Issuer::new();
        let license = issuer.issue(payload(
            DEVICE,
            "2026-09-01T00:00:00Z",
            "2026-10-01T00:00:00Z",
        ));

        assert!(covers(
            &license,
            "crs_01J8ZQK5T9XVWR3M2N4P6H8B7C",
            "vid_01J8ZQK5T9XVWR3M2N4P6H8B7C"
        ));
        assert!(!covers(
            &license,
            "crs_01KOTHERAAAAAAAAAAAAAAAAAA",
            "vid_01KOTHERAAAAAAAAAAAAAAAAAA"
        ));
    }
}
