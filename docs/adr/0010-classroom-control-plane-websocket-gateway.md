# ADR-0010 — Classroom control plane: a WebSocket gateway, not LiveKit data channels

**Status:** Accepted · 2026-09-27

## Context

Besides media, a class has shared state: roles and permissions, the raised-hand queue, the
stage layout, chat, the whiteboard, and capture alerts. ADR-0006 assumed LiveKit data
channels would carry the whiteboard. Two options:

1. **LiveKit data channels + room metadata**, with a server-side bot participant
   (`@livekit/rtc-node`) keeping state for late joiners.
2. **A WebSocket gateway in `services/live`** that owns the state, with LiveKit carrying media
   only.

## Decision

Option 2. The gateway is server-authoritative: one in-memory actor per room applies commands
one at a time, validates them against the capability rules, appends accepted events to a
Redis stream, and fans them out. Clients get a snapshot on join and an event replay from their
last sequence number on reconnect. Everyone's LiveKit token has `canPublishData=false`.

## Consequences

**Good.**
- **Permissions are checked once, on the server.** Data packets are not validated by the SFU,
  so with option 1 every receiver — the Dart app *and* the Egress template — would have to
  re-check every rule, and a modified client could forge ops.
- **Late join and reconnect are simple**: snapshot plus replay. Room metadata is too small for
  a whiteboard, and a bot answering state requests is one more thing to operate.
- **Resilient on throttled networks**: the gateway runs over WSS on port 443. Iranian networks
  often throttle UDP; chat, hands and the board keep working even when media degrades.
- **Testable** with vitest, real `ws` clients and Redis in CI — no LiveKit and no native
  module.

**Bad.**
- Two connections per client, which can fail independently. The UI shows each one's state.
- Whiteboard strokes take one server hop. Batching progress every 40 ms keeps perceived
  latency around 80–150 ms, which is fine for handwriting.
- Scaling out needs room-to-instance pinning (one actor per room, never read-modify-write
  across instances). Fine for one server and 100-person rooms; revisit when that changes.

**Rejected because.** Option 1 spreads the security rules across every client and the
recording template, and still needs a stateful bot for late joiners.
