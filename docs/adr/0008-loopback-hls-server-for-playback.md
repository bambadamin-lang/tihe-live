# ADR-0008 — Loopback HLS server for decryption

**Status:** Accepted · 2026-09-27

## Context

Platform video engines (ExoPlayer, libmpv) need a manifest and segments they can fetch. With
standard encrypted HLS, the engine must be able to fetch the content key, which puts the key
one HTTP request — or one debugger breakpoint — away from an attacker. We also need online and
offline playback to behave identically, and we have two different video engines across
platforms.

## Decision

`packages/secure-core` (Rust) runs an HTTP server bound to `127.0.0.1` on a random port with a
random per-launch bearer token. It serves the video engine a plain manifest and plaintext
segments, decrypting each in memory on request. The content key is unwrapped inside Rust and
held in `mlock`ed memory.

## Consequences

**Good.** The video engine never sees a content key or a key URL. Keys never touch disk or the
Dart heap. Online and offline share one playback path — the only difference is whether
ciphertext comes from MinIO or a local `.tihex` file, which halves the surface for playback
bugs. Both video engines get identical input, so the two-engine cost from ADR-0001 stays
contained.

**Bad.** An extra in-process HTTP hop per segment. And the structural weakness: anyone who
finds the port and token can request plaintext segments themselves. Mitigated by a 256-bit
per-launch token, loopback-only binding, serve-once semantics per segment, and rate limiting to
roughly real-time playback speed — so dumping a lecture takes as long as watching it. Documented
as the known gap in [08-threat-model.md](../08-threat-model.md) (T2).

**Note.** This gap is inherent to ADR-0003, not to this decision: without a TEE, plaintext must
be reachable somewhere. This design shrinks that somewhere to a rate-limited, token-gated,
loopback-only surface.
