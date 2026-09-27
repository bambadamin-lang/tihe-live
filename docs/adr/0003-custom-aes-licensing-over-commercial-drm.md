# ADR-0003 — Custom AES + licence server instead of commercial DRM

**Status:** Accepted · 2026-09-27

## Context

Content protection is the product's reason to exist (see
[01-requirements.md](../01-requirements.md), Q3). The options are commercial DRM
(Widevine L1 / PlayReady / FairPlay) or a custom scheme.

Commercial DRM requires a vendor relationship and recurring cost, and in practice vendor
access and payment are unreliable from Iran. SpotPlayer, the product we are matched against,
uses a custom scheme.

## Decision

Custom AES-128-CTR encryption with a self-hosted Ed25519 licence server, all key handling in
native Rust (`packages/secure-core`), behind a `ContentProtectionProvider` interface.

## Consequences

**Good.** No vendor dependency, no per-stream cost, full control over licence policy (device
limits, offline windows, revocation) which is where the product differentiates. Feature parity
with SpotPlayer is achievable.

**Bad — and stated plainly.** No secure video path. The plaintext must reach the decoder, and
without a TEE that plaintext is reachable by a determined attacker on their own device. A
capture card or a camera defeats the scheme entirely. We accept this: see
[08-threat-model.md](../08-threat-model.md) for what is and is not stopped. The mitigation is
attribution — watermark every frame with the account identity — not prevention.

**Reversibility.** The `ContentProtectionProvider` interface means adding Widevine/PlayReady in
M7 is a second implementation, not a rewrite. That is the main reason the interface exists
before there is a second implementation to justify it.
