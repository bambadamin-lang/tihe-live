# Roadmap

Milestones are ordered by dependency, not by calendar. Each one ends in something you can
demonstrate.

## M0 — Foundation ✅ *(this session)*

Monorepo, docs, Docker Compose stack, shared contracts, API skeleton with the full data
model, Rust protection core with tests, Flutter shell with the first screens.

**Demo:** `docker compose up`, run the API, request an OTP, list courses from seed data,
`cargo test` green.

## M1 — API complete

- Enrollment management, teacher/admin roles and guards
- Persian search tuning (normalization + `pg_trgm`)
- Watch statistics aggregation views (per video, per student, per course)
- Admin CLI: create term/course, enroll students, issue/revoke licences, upload a video
- Real SMS provider (Kavenegar) behind the existing interface

**Demo:** full student lifecycle driven from the CLI and API, no player needed.

## M2a — The packager ✅

- `media-worker`: ffmpeg rendition ladder (1080p/720p/480p + audio-only, never upscaling), poster,
  thumbnail sprite, CEK generation, AES-CTR encryption, HLS packaging, object-storage upload
- Idempotency keyed on the video, progress reporting, failures visible on the row
- A CLI, so a file can be packaged without LiveKit or the admin panel

Split out from the original M2 so the video-management side is never blocked on the live side —
packaging an uploaded file is the same work as packaging a recording, minus the handoff.

**Demo:** `pnpm --filter @tihe/media-worker package ./lecture.mp4 --course crs_… --inline` and the
video is `ready` in the library, its segments encrypted, its content key wrapped with the KEK.

## M2b — The live handoff

- `ingest-worker`: raw egress validation and remux
- LiveKit webhook → ingest → packager, end to end
- Dead-letter handling and retention of the raw master

Contract already specified in [06-recording-pipeline.md](06-recording-pipeline.md), and exercisable
with `infra/scripts/fake-egress.sh` before LiveKit exists.

**Demo:** a LiveKit class ends, and minutes later the video is `ready` in the library with no
human step. This is the moment the two halves of the product connect.

## M3 — Protected online playback

- `secure-core` loopback HLS server wired into Flutter via FFI
- Device registration with X25519 keypair in Android Keystore / Windows DPAPI
- Playback session flow, key unwrapping, key zeroing on pause
- Native-layer watermark overlay with drift
- `FLAG_SECURE` / `WDA_EXCLUDEFROMCAPTURE`, emulator and root detection
- Watch heartbeats and resume

**Demo:** play a lecture on Windows and Android; OBS records a blank window; the watermark
shows the student's number; resume works across devices.

## M4 — Offline

- `.tihex` writer (server-side packaging) and reader (Rust)
- Download queue: pause, resume, retry, progress, storage quota, simultaneous play-while-download
- Device-bound licence issuing, offline verification, expiry, monotonic anti-rollback
- Offline watch-progress queue with sync on reconnect
- Revocation honoured on heartbeat

**Demo:** download a course, turn off networking, watch it; copy the file to another machine
and watch it refuse; revoke the licence and watch access die on reconnect.

**This is the milestone that makes the product a SpotPlayer competitor rather than a video app.**

## M5 — SpotPlayer extras

Chapters with timed titles · PDF/HTML attachments inside the encrypted container ·
student notes and bookmarks · quizzes that gate the next video (`videos.unlock_rule`) ·
completion certificates · playback speed and audio-only mode for low bandwidth.

## M6 — Admin panel (React + Vite)

Course and term management · bulk upload · enrollment import from spreadsheet ·
licence issuing and revocation UI · watch analytics dashboards · **leak investigation: paste
a watermark string, get the account**.

## M7 — Hardening and reach

App Store constraints for iOS/macOS · FairPlay/Widevine L1/PlayReady evaluation ·
forensic A/B watermarking · recording editor (trim, split, merge) · payments (ZarinPal) if
courses are sold directly · behavioural abuse detection.

---

## Live classroom track (L0–L6)

Runs in parallel with M1–M7, owned by the live-classroom session. Design in
[11-live-classroom.md](11-live-classroom.md). Desktop first (ADR-0009).

| Milestone | Scope | Demo |
|---|---|---|
| **L0 — Foundation** | ADRs 0009–0012, live contracts, `services/live` skeleton, `tihe_classroom` theme and example app, `capture_guard` API | example app renders the Persian skeuomorphic stage; `pnpm check` and `flutter test` green |
| **L1 — Join and media (desktop)** | classes/sessions/join, LiveKit tokens, camera and mic, screen-share picker, **capture blocking and watermark from day one** | two desktops in one class; OBS records a black box |
| **L2 — Classroom control** | gateway, roles and capabilities, hands and floor, host controls, participants and chat pods, capture alerts | revoke a student's mic and the SFU drops it; the host sees a recording attempt |
| **L3 — Layouts** | six presets, layout editor, saved layouts, small-screen collapse | host switches layouts and every stage follows |
| **L4 — Whiteboard** | tools, pages, progress/commit sync, undo, manage rights | two people draw at once; a late joiner sees the board |
| **L5 — Recording** | Egress template, auto-record, `metadata.json` ordering, handoff to the pipeline | a class ends and its composite with the board lands in `tihe-raw` |
| **L6 — Mobile** | Android MediaProjection service, iOS broadcast extension, mobile capture detection | a class from an Android phone and an iPhone |

---

## Parked ideas

Recorded here so they are not forgotten and not half-built:

- Live captions / Persian speech-to-text for search inside spoken content
- Auto-generated chapter suggestions from slide changes in the screen share
- Linux desktop build (Flutter supports it; used only for development today)
- Breakout rooms and polls in the live classroom
- Multi-institute tenancy
- Public course catalogue website with a preview trailer per course
- Peer-assisted delivery (students seeding segments) to cut bandwidth cost
