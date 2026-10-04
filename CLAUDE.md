# TIHE Live — conventions for Claude Code sessions

A platform for an educational institute: live virtual classrooms (Adobe Connect–style) whose
recordings flow automatically into a protected course library for Windows/Android/iOS
(SpotPlayer-style licensed offline playback).

## Read first

- `docs/02-architecture.md` — services, ownership, data flows
- `docs/03-content-protection.md` — **read before touching anything involving keys, licences
  or playback.** Protection is the product, not a feature.
- `docs/06-recording-pipeline.md` — read before changing anything that crosses the
  live↔VOD boundary
- `docs/01-requirements.md` — every locked decision and why
- `docs/11-live-classroom.md` — read before touching `services/live` or the classroom packages

## Stack

Flutter (client) · NestJS + Prisma + PostgreSQL (API) · Rust (protection core) ·
Redis + BullMQ (jobs) · MinIO (S3-compatible storage) · LiveKit (live classes) ·
Docker Compose (deploy) · pnpm workspaces + Turborepo (monorepo)

## Layout and ownership

```
apps/player/            Flutter client                      [owner: video dev]
services/api/           NestJS: auth, catalog, licensing     [owner: video dev]
services/media-worker/  ffmpeg transcode/encrypt/package     [owner: video dev]
packages/db/            Prisma schema, migrations, seed — shared
packages/crypto/        server-side crypto: CEK, KEK, licences — shared
services/ingest-worker/ live recording → VOD                 [owner: video dev]
services/live/          classes, LiveKit, classroom gateway  [owner: live-classroom session]
packages/tihe_classroom/ Flutter: live classroom UI           [owner: live-classroom session]
packages/capture_guard/ Flutter plugin: capture blocking     [owner: live-classroom session]
packages/contracts/     shared zod schemas — PR REQUIRED
packages/secure-core/   Rust: crypto, licences, loopback HLS [owner: video dev]
infra/                  compose, nginx, scripts
```

## Hard rules

1. **No secret in Dart.** Content keys, licence verification and decryption live in
   `packages/secure-core` (Rust) only. If you find yourself putting a key in Dart, stop.
2. **Never log a key, a token, an OTP code, or a full phone number.** Mask phone numbers as
   `0912••••567`.
3. **Segments are encrypted before upload.** No plaintext video in MinIO, and manifests carry
   no `#EXT-X-KEY` line.
4. **Never proxy media bytes through the API.** Clients fetch from MinIO by presigned URL.
5. **Timestamps are UTC in the database, always.** Jalali conversion is client-side only.
6. **IDs are prefixed ULIDs** (`usr_`, `crs_`, `vid_`, `lic_`).
7. **Every user-facing error needs a `messageFa`.** See the error envelope in
   `docs/05-api-contracts.md`.
8. **Enrollment is checked on every playback and catalog request.** No endpoint returns content
   the caller cannot watch.
9. **`packages/contracts` changes need a PR** — it is the seam between the two developers.
10. **Anything with crypto, time or permissions in it needs a test.** Those are the things that
    fail silently.

## Commands

```bash
pnpm install                                        # install workspace
docker compose -f infra/docker/compose.dev.yml up -d   # postgres, redis, minio
pnpm check                                          # lint + typecheck everything
pnpm test                                           # all JS tests
pnpm --filter @tihe/api start:dev                   # API on :3000, Swagger at /docs
pnpm --filter @tihe/db migrate:dev                  # apply migrations
pnpm --filter @tihe/db seed                         # seed demo term/course/videos
pnpm --filter @tihe/media-worker package <file> --course crs_… --inline   # package a video
cargo test --manifest-path packages/secure-core/Cargo.toml
pnpm --filter @tihe/live start:dev                  # live classroom on :3100 (services/live/README.md)
cd packages/tihe_classroom/example && flutter run -d macos   # classroom standalone
cd apps/player && flutter run -d windows            # or -d android
```

## Commits

Conventional Commits with an area scope: `feat(api):`, `fix(player):`, `docs(protection):`.
Areas: `api`, `player`, `core`, `media`, `live`, `classroom`, `capture`, `infra`, `docs`, `contracts`.

## Style

- TypeScript: strict mode, no `any`, zod at every boundary, `async/await` over `.then`.
- Rust: no `unwrap()` outside tests, `thiserror` for errors, zero-on-drop for key material.
- Dart: Riverpod for state, `go_router` for navigation, no business logic in widgets.
- Comments explain *why*, not *what*. Match the density of the surrounding code.
