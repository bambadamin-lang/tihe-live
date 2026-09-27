# ADR-0006 — LiveKit for the live classroom

**Status:** Accepted · 2026-09-27 · "Data channels cover whiteboard state" superseded by
[ADR-0010](0010-classroom-control-plane-websocket-gateway.md): LiveKit carries media only.

## Context

We need an Adobe Connect–style classroom: teacher-led, roles and permissions, screen share,
100 participants, and — critically — **server-side recording**, because the recording is what
feeds the video library and clients must not be trusted to record.

Alternatives: a custom Mediasoup/Pion SFU, or Jitsi Meet with Jibri.

## Decision

LiveKit, self-hosted, with LiveKit Egress writing room composite recordings directly to MinIO.

## Consequences

**Good.** Egress recording to S3-compatible storage is built in and is exactly the handoff the
library needs — no custom recording infrastructure. Flutter SDK exists. Data channels cover
whiteboard state. Self-hostable, so ADR-0004 holds.

**Bad.** Egress room composite renders in headless Chrome, which is CPU-hungry: roughly one
Chrome instance per recorded room, so concurrent classes need capacity planning. Another
service to operate.

**Rejected because.** A custom SFU means building recording, reconnection and scaling
ourselves — months, for two people. Jitsi is faster to stand up but harder to shape into a
classroom layout, and Jibri has the same one-browser-per-room cost without LiveKit's API.
