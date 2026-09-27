# Architecture

## System overview

```
              ┌──────── Flutter app (Windows / macOS / Android / iOS) ────────┐
                 │  Dart UI (RTL)                                            │
                 │  secure-core (Rust via FFI) ── OS keystore ── loopback HLS │
                 └───────────────┬───────────────────────┬───────────────────┘
                     HTTPS, cert-pinned          127.0.0.1 only
                                 │
      ┌──────────────────────────┼──────────────────────────────────┐
      │                          │                                  │
┌─────▼──────┐          ┌────────▼────────┐              ┌──────────▼─────────┐
│ services/  │          │ services/       │              │ services/live      │
│ api        │◄─ jobs ─►│ media-worker    │              │ classes, gateway,  │
│ (NestJS)   │  BullMQ  │ ffmpeg/package  │              │ LiveKit orchestr.  │
└─────┬──────┘          └────────┬────────┘              └──────────┬─────────┘
      │                          │                                  │
      │                 ┌────────▼───────────┐                      │
      │                 │ services/          │                      │
      │                 │ ingest-worker      │                      │
      │                 └────────┬───────────┘                      │
┌─────▼──────┐  ┌────────────────▼──────────┐   egress_ended   ┌────▼─────────┐
│ PostgreSQL │  │ MinIO                     │◄─────webhook─────│ LiveKit +    │
│  + Redis   │  │  tihe-raw/ · tihe-vod/    │                  │ Egress       │
└────────────┘  └───────────────────────────┘                  └──────────────┘
```

## Services

### `services/api` — NestJS *(video session)*

The client's main service; `services/live` is the only other one it calls (ADR-0012).
Responsibilities:

- **Auth** — phone OTP, JWT access/refresh, device registration and binding.
- **Catalog** — terms, courses, sections, videos, enrollments, Persian search.
- **Progress** — resume points and the append-only watch-event log.
- **Playback** — mints a playback session: manifest URL, wrapped content key, watermark
  parameters, short TTL.
- **Licensing** — issues, inspects and revokes Ed25519-signed license blobs.
- **Webhooks** — receives LiveKit `egress_ended` and enqueues ingest.

It holds the KEK and the license signing key. It is the only component that can unwrap a
content key, and it only ever hands out keys re-wrapped for one specific device.

### `services/media-worker` — Node + ffmpeg *(video session)*

BullMQ consumer. Takes a source file and produces a publishable video: rendition ladder,
poster, thumbnail sprite, fresh content key, AES-encrypted HLS, upload to `tihe-vod`, and
the `video_assets` + `content_keys` rows. Idempotent and resumable — a crashed job re-runs
without duplicating output.

### `services/ingest-worker` — Node *(video session)*

Bridges live to VOD. Watches for `recordings` rows in `pending`, validates and remuxes the
raw egress output, then hands off to `media-worker`. Kept separate because raw-recording
handling is the part most likely to need per-engine quirks, and isolating it keeps
`media-worker` engine-agnostic.

### `services/live` — live classroom *(live-classroom session)*

Classes and sessions, join tokens, room lifecycle, and the **classroom gateway**: a WebSocket
control plane for roles and permissions, raised hands, layouts, chat, the whiteboard and
capture alerts (ADR-0010). Starts and stops Egress with its own recording template. Its own
database `tihe_live` on the same Postgres server; reaches the API only through the
`CourseDirectory` interface (ADR-0012). Clients call it at `/v1/live/*`. **Nothing in the
video pipeline reaches into this service** — the contract between the two is the webhook plus
the raw bucket layout, both specified in [06-recording-pipeline.md](06-recording-pipeline.md).
Full design: [11-live-classroom.md](11-live-classroom.md).

### `apps/player` — Flutter *(video session)*

Two layers:

- **Dart** — UI, navigation, API calls, download queue orchestration, offline metadata
  cache. Holds no content keys, ever.
- **`secure-core` (Rust, via FFI)** — license verification, key unwrapping, device
  fingerprinting, segment decryption, and a loopback HLS server. All secrets live here.

## Packages

### `packages/contracts`

Zod schemas and inferred TypeScript types for every entity, request and response, plus the
error envelope, the license blob layout and the LiveKit webhook payloads. Emits an OpenAPI
document that the Flutter client generates its models from, so a breaking API change breaks
the build rather than production.

**This is the seam between the two developers.** Changes require a PR.

### `packages/tihe_classroom` and `packages/capture_guard` *(live-classroom session)*

Flutter packages the app imports. `tihe_classroom` is the whole classroom UI with its own
skeuomorphic Persian theme; it runs standalone through its `example/` app. `capture_guard` is
a Flutter plugin that blocks and detects screen capture on all four platforms (ADR-0011) and
is shared with the player.

### `packages/secure-core`

A Rust crate, compiled into the Flutter app for each platform. Also usable as a CLI for
testing (`tihex inspect`, `tihex pack`). Pure Rust with no Flutter dependency at its core,
so it is unit-testable in CI on Linux without a device.

## Why the loopback HLS server

This is the least obvious design choice, so it is worth stating plainly.

The problem: platform video engines (ExoPlayer on Android, libmpv on Windows) need a
manifest and segments. If we hand them encrypted HLS with a key URL, the key must be
fetchable by the engine — which means it exists in a place a debugger or a patched build can
read. Standard AES-128 HLS puts the key one HTTP request away from anyone.

The solution: `secure-core` starts an HTTP server bound to `127.0.0.1` on a random port at
app launch, protected by a random per-launch bearer token. It serves the player a plain,
unencrypted manifest and plaintext segments, decrypting each segment in memory as it is
requested. The real content key is unwrapped inside Rust, held in locked (non-swappable)
memory, and zeroed when playback stops.

Consequences:

- The video engine never sees a content key or a remote key URL.
- **Online and offline use the exact same playback path** — the only difference is whether
  the encrypted bytes come from MinIO or from a local `.tihex` file. One player, one set of
  bugs.
- Keys never touch disk in plaintext, and never enter the Dart heap.
- Cost: an extra in-process HTTP hop, and the loopback port must be firewalled to
  loopback-only (it is, by binding address) and token-gated (it is).

## Data flow: a class becomes a library video

1. Teacher starts a class → `services/live` creates a LiveKit room (named after the session
   id) and starts a room composite egress, rendered by its recording template, writing to
   `s3://tihe-raw/recordings/{classId}/{sessionId}/`.
2. Class ends → LiveKit fires `egress_ended` → `POST /webhooks/livekit` (signature verified).
3. API writes a `recordings` row (`status: pending`) and enqueues `ingest:process`.
4. `ingest-worker` validates and remuxes, then enqueues `media:package`.
5. `media-worker` transcodes the ladder, generates poster + sprite, creates a content key,
   encrypts and packages HLS, uploads to `tihe-vod`, writes `video_assets` and
   `content_keys`, sets `videos.status = ready`.
6. The video appears in the enrolled students' library, attached to the course the class
   belonged to.

## Data flow: a student plays a video

1. `POST /playback/{videoId}/session` with a registered device id.
2. API checks enrollment, license validity, device trust and device count. Unwraps the
   content key with the KEK, re-wraps it for that device's public key, and returns a
   playback session: manifest URL, wrapped key, watermark parameters, TTL.
3. Dart hands the session to `secure-core` over FFI.
4. Rust unwraps the key using the device private key from the OS keystore, starts the
   loopback server, returns a `http://127.0.0.1:{port}/{token}/master.m3u8` URL.
5. The video engine plays that URL. Dart composites the watermark overlay in the native
   layer.
6. The player posts watch heartbeats; the API appends `watch_events` and updates
   `watch_progress`.

## Folder ownership, restated

```
apps/player/               video session
services/api/              video session
services/media-worker/     video session
services/ingest-worker/    video session
packages/secure-core/      video session
services/live/             live-classroom session
packages/tihe_classroom/   live-classroom session
packages/capture_guard/    live-classroom session (shared with the player)
packages/contracts/        shared — PR required
infra/                     shared — PR required
docs/                      shared
```
