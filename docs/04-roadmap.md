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

## M2 — Media pipeline

- `media-worker`: ffmpeg rendition ladder (1080p/720p/480p + audio-only), poster, thumbnail
  sprite, CEK generation, AES-CTR encryption, HLS packaging, MinIO upload
- `ingest-worker`: raw egress validation and remux
- LiveKit webhook end to end
- Job retry, idempotency, dead-letter handling, progress reporting

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

iOS build and App Store constraints · FairPlay/Widevine L1/PlayReady evaluation ·
forensic A/B watermarking · recording editor (trim, split, merge) · payments (ZarinPal) if
courses are sold directly · behavioural abuse detection.

---

## Parked ideas

Recorded here so they are not forgotten and not half-built:

- Live captions / Persian speech-to-text for search inside spoken content
- Auto-generated chapter suggestions from slide changes in the screen share
- Mac and Linux desktop builds (Flutter supports both; no demand stated yet)
- Multi-institute tenancy
- Public course catalogue website with a preview trailer per course
- Peer-assisted delivery (students seeding segments) to cut bandwidth cost
