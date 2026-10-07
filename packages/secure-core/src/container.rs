//! The `.tihex` offline container.
//!
//! ```text
//! MAGIC "TIHEX\0" (6) | VERSION u16 | HEADER_LEN u32 | HEADER (CBOR) | SIG (64) | PAYLOAD
//! ```
//!
//! Two properties carry the whole offline protection story:
//!
//! 1. The header is **signed by the server**, and it contains the expiry, the device id and the
//!    wrapped key. A student cannot extend their own access or retarget the file, because they
//!    cannot re-sign the header.
//! 2. The wrapped key is sealed to **one device's** public key, whose private half never leaves
//!    the OS keystore. Copying the file elsewhere produces something unopenable — not a file
//!    that plays with a warning.
//!
//! The segment index also makes partial files useful: a download interrupted halfway is valid
//! and playable up to its last complete segment, which is what "download and watch at the same
//! time" needs.

use std::io::{Read, Seek, SeekFrom, Write};

use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};

use crate::crypto::{apply_segment_cipher, unwrap_key_for_device, ContentKey, DeviceKeypair};
use crate::error::{CoreError, Result};
use crate::license::parse_rfc3339;

pub const MAGIC: &[u8; 6] = b"TIHEX\0";
pub const VERSION: u16 = 1;
const SIGNATURE_LEN: usize = 64;
const PREAMBLE_LEN: usize = 6 + 2 + 4;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SegmentEntry {
    pub rendition: String,
    pub seq: u64,
    /// Offset from the start of the payload region, not from the start of the file.
    pub offset: u64,
    pub len: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RenditionEntry {
    pub id: String,
    pub label: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub bitrate: u64,
    pub segment_count: u64,
    /// Seconds per segment, for building the local manifest.
    pub target_duration: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AttachmentEntry {
    pub id: String,
    pub name: String,
    pub mime: String,
    pub offset: u64,
    pub len: u64,
    pub copyable: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ContainerHeader {
    pub v: u16,
    pub video_id: String,
    pub title: String,
    pub duration_ms: u64,
    pub created_at: String,
    pub key_id: String,
    /// Content key sealed to `device_id`'s public key.
    pub wrapped_key: Vec<u8>,
    pub license_id: String,
    pub device_id: String,
    pub not_after: String,
    pub revocation_epoch: u64,
    pub renditions: Vec<RenditionEntry>,
    pub segments: Vec<SegmentEntry>,
    pub attachments: Vec<AttachmentEntry>,
}

/// A container opened for reading. Holds the file handle and the verified header; the content
/// key is only unwrapped on demand so it spends as little time in memory as possible.
pub struct Container<R: Read + Seek> {
    reader: R,
    header: ContainerHeader,
    payload_start: u64,
}

impl<R: Read + Seek> Container<R> {
    /// Reads and verifies a container's header.
    ///
    /// Verification happens here, before any payload byte is touched, so a tampered file is
    /// rejected rather than partially played.
    pub fn open(mut reader: R, license_public_key: &[u8; 32]) -> Result<Self> {
        let mut magic = [0u8; 6];
        reader.read_exact(&mut magic)?;
        if &magic != MAGIC {
            return Err(CoreError::InvalidContainer("bad magic"));
        }

        let mut version_bytes = [0u8; 2];
        reader.read_exact(&mut version_bytes)?;
        let version = u16::from_be_bytes(version_bytes);
        if version != VERSION {
            return Err(CoreError::InvalidContainer("unsupported version"));
        }

        let mut len_bytes = [0u8; 4];
        reader.read_exact(&mut len_bytes)?;
        let header_len = u32::from_be_bytes(len_bytes) as usize;
        // A hostile file could claim a gigabyte-long header to exhaust memory.
        if header_len == 0 || header_len > 8 * 1024 * 1024 {
            return Err(CoreError::InvalidContainer("header length out of range"));
        }

        let mut header_bytes = vec![0u8; header_len];
        reader.read_exact(&mut header_bytes)?;

        let mut signature_bytes = [0u8; SIGNATURE_LEN];
        reader.read_exact(&mut signature_bytes)?;

        let verifying_key =
            VerifyingKey::from_bytes(license_public_key).map_err(|_| CoreError::BadSignature)?;
        verifying_key
            .verify(&header_bytes, &Signature::from_bytes(&signature_bytes))
            .map_err(|_| CoreError::BadSignature)?;

        let header: ContainerHeader = serde_cbor::from_slice(&header_bytes)?;

        Ok(Self {
            reader,
            header,
            payload_start: (PREAMBLE_LEN + header_len + SIGNATURE_LEN) as u64,
        })
    }

    pub fn header(&self) -> &ContainerHeader {
        &self.header
    }

    /// Checks the container is usable on this device right now.
    ///
    /// Separate from `open` because a valid file that has simply expired should produce a
    /// specific, explainable error rather than looking like corruption.
    pub fn check_usable(
        &self,
        device_id: &str,
        now: time::OffsetDateTime,
        current_epoch: u64,
    ) -> Result<()> {
        if self.header.device_id != device_id {
            return Err(CoreError::WrongDevice);
        }
        if self.header.revocation_epoch < current_epoch {
            return Err(CoreError::LicenseRevoked);
        }
        if now > parse_rfc3339(&self.header.not_after)? {
            return Err(CoreError::LicenseExpired);
        }
        Ok(())
    }

    /// Unwraps the content key. The caller should hold the result for as short a time as
    /// possible; it zeroes itself on drop.
    pub fn content_key(&self, keypair: &DeviceKeypair) -> Result<ContentKey> {
        unwrap_key_for_device(&self.header.wrapped_key, keypair, &self.header.device_id)
    }

    /// Reads one segment and decrypts it in memory. Plaintext is never written to disk.
    pub fn read_segment(&mut self, key: &ContentKey, rendition: &str, seq: u64) -> Result<Vec<u8>> {
        let entry = self
            .header
            .segments
            .iter()
            .find(|s| s.rendition == rendition && s.seq == seq)
            .ok_or(CoreError::NotFound)?
            .clone();

        let mut buf = vec![0u8; entry.len as usize];
        self.reader
            .seek(SeekFrom::Start(self.payload_start + entry.offset))?;
        self.reader.read_exact(&mut buf)?;

        let iv = crate::crypto::segment_iv(&self.header.key_id, seq);
        apply_segment_cipher(key, &iv, &mut buf);
        Ok(buf)
    }

    /// How many segments of a rendition are actually present in the file.
    ///
    /// A partially downloaded container is legitimate — this is what lets playback start before
    /// the download finishes.
    pub fn available_segments(&mut self, rendition: &str) -> Result<u64> {
        let file_len = self.reader.seek(SeekFrom::End(0))?;
        let available = self
            .header
            .segments
            .iter()
            .filter(|s| s.rendition == rendition)
            .filter(|s| self.payload_start + s.offset + s.len <= file_len)
            .count();
        Ok(available as u64)
    }

    /// Builds the plaintext HLS media playlist served to the local video engine.
    ///
    /// Note what is absent: no `#EXT-X-KEY` line. The engine receives already-decrypted
    /// segments from the loopback server, so it never needs a key and never sees one.
    pub fn media_playlist(&mut self, rendition: &str, base_url: &str) -> Result<String> {
        let entry = self
            .header
            .renditions
            .iter()
            .find(|r| r.label == rendition || r.id == rendition)
            .ok_or(CoreError::NotFound)?
            .clone();

        let available = self.available_segments(&entry.label)?;

        let mut out = String::with_capacity(128 + available as usize * 48);
        out.push_str("#EXTM3U\n#EXT-X-VERSION:3\n");
        out.push_str(&format!(
            "#EXT-X-TARGETDURATION:{}\n",
            entry.target_duration
        ));
        out.push_str("#EXT-X-MEDIA-SEQUENCE:0\n");
        out.push_str("#EXT-X-PLAYLIST-TYPE:VOD\n");

        for seq in 0..available {
            out.push_str(&format!("#EXTINF:{:.3},\n", entry.target_duration as f64));
            out.push_str(&format!("{base_url}/{}/{seq}.ts\n", entry.label));
        }

        // Only mark the playlist complete when every segment is present; otherwise the engine
        // would stop at the download's current edge instead of waiting for more.
        if available == entry.segment_count {
            out.push_str("#EXT-X-ENDLIST\n");
        }
        Ok(out)
    }
}

/// Writes a container. The header must already be signed by the server — this crate does not
/// hold a signing key, and must not.
pub struct ContainerWriter<W: Write> {
    writer: W,
}

impl<W: Write> ContainerWriter<W> {
    /// Writes the preamble, header and signature, leaving the writer positioned for payload.
    pub fn begin(
        mut writer: W,
        header_bytes: &[u8],
        signature: &[u8; SIGNATURE_LEN],
    ) -> Result<Self> {
        writer.write_all(MAGIC)?;
        writer.write_all(&VERSION.to_be_bytes())?;
        writer.write_all(&(header_bytes.len() as u32).to_be_bytes())?;
        writer.write_all(header_bytes)?;
        writer.write_all(signature)?;
        Ok(Self { writer })
    }

    /// Appends already-encrypted segment bytes, in index order.
    pub fn append_segment(&mut self, ciphertext: &[u8]) -> Result<()> {
        self.writer.write_all(ciphertext)?;
        Ok(())
    }

    pub fn finish(mut self) -> Result<W> {
        self.writer.flush()?;
        Ok(self.writer)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::{segment_iv, wrap_key_for_device};
    use crate::license::test_support::Issuer;
    use ed25519_dalek::Signer;
    use std::io::Cursor;
    use time::macros::datetime;

    const DEVICE: &str = "dev_01J8ZQK5T9XVWR3M2N4P6H8B7C";

    struct Fixture {
        bytes: Vec<u8>,
        plaintexts: Vec<Vec<u8>>,
    }

    /// Builds a container the way the server would: wrap the key, sign the header, append
    /// ciphertext.
    fn build(
        issuer: &Issuer,
        device: &DeviceKeypair,
        device_id: &str,
        not_after: &str,
        epoch: u64,
        segment_count: u64,
    ) -> Fixture {
        let key = ContentKey::random();
        let wrapped = wrap_key_for_device(&key, &device.public_bytes(), device_id).unwrap();

        let mut plaintexts = Vec::new();
        let mut ciphertexts = Vec::new();
        let mut segments = Vec::new();
        let mut offset = 0u64;

        for seq in 0..segment_count {
            let plain = format!("segment {seq} of an encrypted lecture").into_bytes();
            let mut cipher = plain.clone();
            apply_segment_cipher(&key, &segment_iv("ck_fixture", seq), &mut cipher);

            segments.push(SegmentEntry {
                rendition: "720p".into(),
                seq,
                offset,
                len: cipher.len() as u64,
            });
            offset += cipher.len() as u64;
            plaintexts.push(plain);
            ciphertexts.push(cipher);
        }

        let header = ContainerHeader {
            v: VERSION,
            video_id: "vid_01J8ZQK5T9XVWR3M2N4P6H8B7C".into(),
            title: "جلسه ۴ — مشتق".into(),
            duration_ms: 90 * 60 * 1000,
            created_at: "2026-09-15T12:00:00Z".into(),
            key_id: "ck_fixture".into(),
            wrapped_key: wrapped,
            license_id: "lic_01J8ZQK5T9XVWR3M2N4P6H8B7C".into(),
            device_id: device_id.into(),
            not_after: not_after.into(),
            revocation_epoch: epoch,
            renditions: vec![RenditionEntry {
                id: "ast_720".into(),
                label: "720p".into(),
                width: Some(1280),
                height: Some(720),
                bitrate: 1_800_000,
                segment_count,
                target_duration: 6,
            }],
            segments,
            attachments: vec![],
        };

        let header_bytes = serde_cbor::to_vec(&header).unwrap();
        let signature: [u8; 64] = issuer.signing.sign(&header_bytes).to_bytes();

        let mut writer = ContainerWriter::begin(Vec::new(), &header_bytes, &signature).unwrap();
        for c in &ciphertexts {
            writer.append_segment(c).unwrap();
        }

        Fixture {
            bytes: writer.finish().unwrap(),
            plaintexts,
        }
    }

    #[test]
    fn a_container_round_trips_on_the_right_device() {
        let issuer = Issuer::new();
        let device = DeviceKeypair::generate();
        let f = build(&issuer, &device, DEVICE, "2099-01-01T00:00:00Z", 1, 3);

        let mut c = Container::open(Cursor::new(f.bytes), &issuer.public_key()).unwrap();
        c.check_usable(DEVICE, datetime!(2026-09-20 00:00 UTC), 1)
            .unwrap();

        let key = c.content_key(&device).unwrap();
        for (seq, expected) in f.plaintexts.iter().enumerate() {
            let got = c.read_segment(&key, "720p", seq as u64).unwrap();
            assert_eq!(&got, expected, "segment {seq} did not decrypt correctly");
        }
    }

    #[test]
    fn a_container_copied_to_another_device_cannot_be_opened() {
        // The headline property of offline protection: copying the file gets you nothing.
        let issuer = Issuer::new();
        let owner = DeviceKeypair::generate();
        let thief = DeviceKeypair::generate();
        let f = build(&issuer, &owner, DEVICE, "2099-01-01T00:00:00Z", 1, 2);

        let c = Container::open(Cursor::new(f.bytes), &issuer.public_key()).unwrap();

        // The header still reads — it is not secret — but the key will not unwrap.
        assert!(matches!(c.content_key(&thief), Err(CoreError::KeyUnwrap)));
    }

    #[test]
    fn a_container_bound_to_another_device_id_is_refused() {
        let issuer = Issuer::new();
        let device = DeviceKeypair::generate();
        let f = build(
            &issuer,
            &device,
            "dev_01KOTHERAAAAAAAAAAAAAAAAAA",
            "2099-01-01T00:00:00Z",
            1,
            1,
        );

        let c = Container::open(Cursor::new(f.bytes), &issuer.public_key()).unwrap();

        assert!(matches!(
            c.check_usable(DEVICE, datetime!(2026-09-20 00:00 UTC), 1),
            Err(CoreError::WrongDevice)
        ));
    }

    #[test]
    fn an_expired_container_is_refused() {
        let issuer = Issuer::new();
        let device = DeviceKeypair::generate();
        let f = build(&issuer, &device, DEVICE, "2026-09-01T00:00:00Z", 1, 1);

        let c = Container::open(Cursor::new(f.bytes), &issuer.public_key()).unwrap();

        assert!(matches!(
            c.check_usable(DEVICE, datetime!(2026-09-20 00:00 UTC), 1),
            Err(CoreError::LicenseExpired)
        ));
    }

    #[test]
    fn a_revoked_container_is_refused() {
        let issuer = Issuer::new();
        let device = DeviceKeypair::generate();
        let f = build(&issuer, &device, DEVICE, "2099-01-01T00:00:00Z", 2, 1);

        let c = Container::open(Cursor::new(f.bytes), &issuer.public_key()).unwrap();

        // Server has advanced to epoch 5; this file was written at 2.
        assert!(matches!(
            c.check_usable(DEVICE, datetime!(2026-09-20 00:00 UTC), 5),
            Err(CoreError::LicenseRevoked)
        ));
    }

    #[test]
    fn editing_the_header_breaks_the_signature() {
        // The attack this blocks: flip a byte in not_after to extend access.
        let issuer = Issuer::new();
        let device = DeviceKeypair::generate();
        let mut f = build(&issuer, &device, DEVICE, "2026-09-01T00:00:00Z", 1, 1);

        // Corrupt a byte inside the header region.
        f.bytes[PREAMBLE_LEN + 20] ^= 0xff;

        assert!(matches!(
            Container::open(Cursor::new(f.bytes), &issuer.public_key()),
            Err(CoreError::BadSignature)
        ));
    }

    #[test]
    fn a_header_signed_by_the_wrong_key_is_rejected() {
        let real = Issuer::new();
        let forger = Issuer::new();
        let device = DeviceKeypair::generate();
        let f = build(&forger, &device, DEVICE, "2099-01-01T00:00:00Z", 1, 1);

        assert!(matches!(
            Container::open(Cursor::new(f.bytes), &real.public_key()),
            Err(CoreError::BadSignature)
        ));
    }

    #[test]
    fn a_file_with_bad_magic_is_rejected() {
        let issuer = Issuer::new();
        assert!(matches!(
            Container::open(
                Cursor::new(b"not a tihex file at all".to_vec()),
                &issuer.public_key()
            ),
            Err(CoreError::InvalidContainer(_))
        ));
    }

    #[test]
    fn an_absurd_header_length_is_rejected_without_allocating() {
        // A hostile file must not be able to make us allocate a gigabyte.
        let issuer = Issuer::new();
        let mut bytes = Vec::new();
        bytes.extend_from_slice(MAGIC);
        bytes.extend_from_slice(&VERSION.to_be_bytes());
        bytes.extend_from_slice(&u32::MAX.to_be_bytes());

        assert!(matches!(
            Container::open(Cursor::new(bytes), &issuer.public_key()),
            Err(CoreError::InvalidContainer("header length out of range"))
        ));
    }

    #[test]
    fn a_partial_download_reports_only_complete_segments() {
        // This is what makes play-while-downloading work: the file is usable up to its edge.
        let issuer = Issuer::new();
        let device = DeviceKeypair::generate();
        let mut f = build(&issuer, &device, DEVICE, "2099-01-01T00:00:00Z", 1, 4);

        let full_len = f.bytes.len();
        f.bytes.truncate(full_len - 10); // cut the last segment short

        let mut c = Container::open(Cursor::new(f.bytes), &issuer.public_key()).unwrap();
        assert_eq!(c.available_segments("720p").unwrap(), 3);
    }

    #[test]
    fn a_partial_playlist_omits_the_endlist_tag() {
        let issuer = Issuer::new();
        let device = DeviceKeypair::generate();
        let mut f = build(&issuer, &device, DEVICE, "2099-01-01T00:00:00Z", 1, 4);
        let full_len = f.bytes.len();
        f.bytes.truncate(full_len - 10);

        let mut c = Container::open(Cursor::new(f.bytes), &issuer.public_key()).unwrap();
        let playlist = c
            .media_playlist("720p", "http://127.0.0.1:9999/tok")
            .unwrap();

        assert!(
            !playlist.contains("#EXT-X-ENDLIST"),
            "engine must keep waiting for more"
        );
        assert_eq!(playlist.matches("#EXTINF").count(), 3);
    }

    #[test]
    fn a_complete_playlist_carries_the_endlist_tag_and_no_key_line() {
        let issuer = Issuer::new();
        let device = DeviceKeypair::generate();
        let f = build(&issuer, &device, DEVICE, "2099-01-01T00:00:00Z", 1, 3);

        let mut c = Container::open(Cursor::new(f.bytes), &issuer.public_key()).unwrap();
        let playlist = c
            .media_playlist("720p", "http://127.0.0.1:9999/tok")
            .unwrap();

        assert!(playlist.contains("#EXT-X-ENDLIST"));
        // The engine must never be handed a key URL — that is the entire point of the loopback
        // server. See docs/adr/0008.
        assert!(!playlist.contains("EXT-X-KEY"));
    }

    #[test]
    fn requesting_an_unknown_segment_fails_cleanly() {
        let issuer = Issuer::new();
        let device = DeviceKeypair::generate();
        let f = build(&issuer, &device, DEVICE, "2099-01-01T00:00:00Z", 1, 2);

        let mut c = Container::open(Cursor::new(f.bytes), &issuer.public_key()).unwrap();
        let key = c.content_key(&device).unwrap();

        assert!(matches!(
            c.read_segment(&key, "720p", 99),
            Err(CoreError::NotFound)
        ));
    }
}
