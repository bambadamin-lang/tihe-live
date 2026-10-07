//! The loopback HLS server: token, port and serve-once policy.
//!
//! Rationale is in `docs/adr/0008-loopback-hls-server-for-playback.md`. Short version: the video
//! engine needs fetchable segments, so we hand it plaintext over `127.0.0.1` rather than handing
//! it a content key it could be made to leak.
//!
//! This module holds the **policy** — access control, serve-once accounting, rate limiting — kept
//! separate from the HTTP plumbing so it can be tested without binding a socket. The socket
//! wiring lands in M3 with the Flutter integration.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use rand::RngCore;
use subtle::ConstantTimeEq;

use crate::error::{CoreError, Result};

/// A per-launch bearer token. Random, never logged, never written to disk, rotated per session.
#[derive(Clone)]
pub struct SessionToken(String);

impl SessionToken {
    pub fn generate() -> Self {
        let mut bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut bytes);
        Self(hex::encode(bytes))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Constant-time comparison. A timing oracle on a loopback endpoint is a stretch, but the
    /// token is the only thing standing between a local process and plaintext segments, so it
    /// costs nothing to be careful.
    pub fn matches(&self, candidate: &str) -> bool {
        if candidate.len() != self.0.len() {
            return false;
        }
        self.0.as_bytes().ct_eq(candidate.as_bytes()).into()
    }
}

impl std::fmt::Debug for SessionToken {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("SessionToken(redacted)")
    }
}

/// Why a segment request was refused.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RefusalReason {
    BadToken,
    AlreadyServed,
    RateLimited,
}

/// Enforces the access policy for one playback session.
///
/// Two limits, both aimed at the dump-the-whole-lecture attack from threat model T2:
///
/// * **Serve once.** Normal playback fetches each segment a single time; the engine buffers
///   rather than re-requesting. A second request for the same segment is therefore either a seek
///   backwards — handled by `allow_reseek` — or a scrape.
/// * **Rate limit.** Serving is capped near real-time playback speed, so dumping a 90-minute
///   lecture takes about 90 minutes instead of seconds.
pub struct LoopbackPolicy {
    token: SessionToken,
    served: HashMap<(String, u64), u32>,
    /// Segments a client may fetch beyond real-time pace, so buffering and short seeks work.
    burst_allowance: u32,
    segment_duration: Duration,
    started: Instant,
    served_count: u32,
    allow_reseek: bool,
}

impl LoopbackPolicy {
    pub fn new(segment_duration_seconds: u64) -> Self {
        Self {
            token: SessionToken::generate(),
            served: HashMap::new(),
            // Roughly 30 seconds of video for a 6-second segment: enough for the engine to
            // pre-buffer and for a student to scrub, not enough to drain a lecture.
            burst_allowance: 5,
            segment_duration: Duration::from_secs(segment_duration_seconds.max(1)),
            started: Instant::now(),
            served_count: 0,
            allow_reseek: true,
        }
    }

    pub fn token(&self) -> &SessionToken {
        &self.token
    }

    /// The URL path prefix the engine is given. Includes the token, so a process that never saw
    /// the manifest URL cannot construct a valid request.
    pub fn base_path(&self) -> String {
        format!("/{}", self.token.as_str())
    }

    /// Decides whether to serve a segment, at a given moment.
    ///
    /// `now` is a parameter rather than read from the clock so the rate limiter is testable
    /// without sleeping.
    pub fn authorize_at(
        &mut self,
        token: &str,
        rendition: &str,
        seq: u64,
        now: Instant,
    ) -> Result<()> {
        if !self.token.matches(token) {
            return Err(CoreError::InvalidContainer("unauthorized"));
        }

        let key = (rendition.to_string(), seq);
        let previous = self.served.get(&key).copied().unwrap_or(0);

        // A handful of repeats is ordinary: the engine re-reads after a seek or a stall. Many
        // repeats of the same segment is not playback.
        if previous > 0 && (!self.allow_reseek || previous >= 3) {
            return Err(CoreError::InvalidContainer("already served"));
        }

        // Real-time pacing, with a burst so playback starts promptly.
        let elapsed = now.saturating_duration_since(self.started);
        let entitled =
            (elapsed.as_secs() / self.segment_duration.as_secs()) as u32 + self.burst_allowance;
        if self.served_count >= entitled {
            return Err(CoreError::InvalidContainer("rate limited"));
        }

        self.served.insert(key, previous + 1);
        self.served_count += 1;
        Ok(())
    }

    /// Convenience wrapper using the current clock.
    pub fn authorize(&mut self, token: &str, rendition: &str, seq: u64) -> Result<()> {
        self.authorize_at(token, rendition, seq, Instant::now())
    }

    pub fn served_count(&self) -> u32 {
        self.served_count
    }
}

/// Rewrites a master playlist to point at the loopback server.
///
/// The original manifest is never handed to the engine, so any `#EXT-X-KEY` line it carries is
/// dropped here rather than relied upon to be absent.
pub fn local_master_playlist(renditions: &[(String, u64, u32, u32)], base_url: &str) -> String {
    let mut out = String::from("#EXTM3U\n#EXT-X-VERSION:3\n");
    for (label, bitrate, width, height) in renditions {
        out.push_str(&format!(
            "#EXT-X-STREAM-INF:BANDWIDTH={bitrate},RESOLUTION={width}x{height}\n"
        ));
        out.push_str(&format!("{base_url}/{label}/index.m3u8\n"));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn policy() -> LoopbackPolicy {
        LoopbackPolicy::new(6)
    }

    #[test]
    fn a_valid_token_is_accepted() {
        let mut p = policy();
        let token = p.token().as_str().to_string();
        assert!(p.authorize(&token, "720p", 0).is_ok());
    }

    #[test]
    fn a_wrong_token_is_refused() {
        let mut p = policy();
        assert!(p.authorize("0".repeat(64).as_str(), "720p", 0).is_err());
    }

    #[test]
    fn a_truncated_token_is_refused() {
        let mut p = policy();
        let token = p.token().as_str()[..32].to_string();
        assert!(p.authorize(&token, "720p", 0).is_err());
    }

    #[test]
    fn tokens_differ_between_sessions() {
        let a = policy();
        let b = policy();
        assert_ne!(a.token().as_str(), b.token().as_str());
    }

    #[test]
    fn a_token_is_256_bits_of_hex() {
        assert_eq!(policy().token().as_str().len(), 64);
    }

    #[test]
    fn debug_never_prints_the_token() {
        let p = policy();
        let printed = format!("{:?}", p.token());
        assert!(!printed.contains(p.token().as_str()));
    }

    #[test]
    fn a_few_repeats_are_allowed_for_seeking() {
        // A student scrubbing backwards re-requests segments. Blocking that would break playback.
        let mut p = policy();
        let token = p.token().as_str().to_string();
        let now = Instant::now();

        assert!(p.authorize_at(&token, "720p", 0, now).is_ok());
        assert!(p.authorize_at(&token, "720p", 0, now).is_ok());
    }

    #[test]
    fn hammering_one_segment_is_refused() {
        let mut p = policy();
        let token = p.token().as_str().to_string();
        let now = Instant::now();

        p.authorize_at(&token, "720p", 0, now).unwrap();
        p.authorize_at(&token, "720p", 0, now).unwrap();
        p.authorize_at(&token, "720p", 0, now).unwrap();

        assert!(p.authorize_at(&token, "720p", 0, now).is_err());
    }

    #[test]
    fn the_burst_allowance_lets_playback_start_immediately() {
        // Without a burst, the engine could not pre-buffer and playback would stutter at the
        // start of every video.
        let mut p = policy();
        let token = p.token().as_str().to_string();
        let now = Instant::now();

        for seq in 0..5 {
            assert!(
                p.authorize_at(&token, "720p", seq, now).is_ok(),
                "segment {seq} should be within the burst allowance"
            );
        }
    }

    #[test]
    fn dumping_faster_than_real_time_is_refused() {
        // The T2 mitigation: a scraper gets the burst, then has to wait like a viewer.
        let mut p = policy();
        let token = p.token().as_str().to_string();
        let now = Instant::now();

        for seq in 0..5 {
            p.authorize_at(&token, "720p", seq, now).unwrap();
        }

        assert!(
            p.authorize_at(&token, "720p", 5, now).is_err(),
            "a sixth immediate segment should be rate limited"
        );
    }

    #[test]
    fn waiting_earns_more_segments() {
        let mut p = policy();
        let token = p.token().as_str().to_string();
        let start = Instant::now();

        for seq in 0..5 {
            p.authorize_at(&token, "720p", seq, start).unwrap();
        }
        assert!(p.authorize_at(&token, "720p", 5, start).is_err());

        // Six seconds later — one segment duration — one more is due.
        let later = start + Duration::from_secs(6);
        assert!(p.authorize_at(&token, "720p", 5, later).is_ok());
    }

    #[test]
    fn the_base_path_contains_the_token() {
        let p = policy();
        assert_eq!(p.base_path(), format!("/{}", p.token().as_str()));
    }

    #[test]
    fn the_master_playlist_lists_every_rendition_and_no_key() {
        let playlist = local_master_playlist(
            &[
                ("1080p".into(), 4_500_000, 1920, 1080),
                ("720p".into(), 1_800_000, 1280, 720),
            ],
            "http://127.0.0.1:41234/abc",
        );

        assert!(playlist.contains("1080p/index.m3u8"));
        assert!(playlist.contains("720p/index.m3u8"));
        assert!(playlist.contains("RESOLUTION=1920x1080"));
        assert!(!playlist.contains("EXT-X-KEY"));
    }
}
