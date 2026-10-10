# Requirements & Decisions Record

This is the record of the questions asked during project kickoff and the answers given. When
a decision here turns out to be wrong, edit this file and add an ADR in [adr/](adr/) — do not
silently diverge in code.

Kickoff date: 2026-09-27 · Team: 2 developers.

---

## Ownership

| Owner | Owns |
|---|---|
| **Video session** (`hsn.eyvazian@gmail.com`) | Video management: `services/api`, `services/media-worker`, `services/ingest-worker`, `apps/player`, `packages/secure-core` |
| **Live-classroom session** | Live classroom: `services/live`, `packages/tihe_classroom`, `packages/capture_guard`, the LiveKit deployment |
| **Shared, PR required** | `packages/contracts`, `infra/`, `docs/` |

### Live classroom requirements (added 2026-09-27)

Stated by the institute for the live classroom, designed in
[11-live-classroom.md](11-live-classroom.md):

- Apps for **Windows, Android, iOS and macOS** ([ADR-0009](adr/0009-four-platforms-classroom-desktop-first.md)); the classroom ships desktop-first.
- Screen sharing and webcam.
- A whiteboard with several pen types.
- Raised hands and levels of access in class.
- Class layouts with recommended presets.
- **Screen recording is banned**: recording the screen or the app window produces censored output; detection alerts the host ([ADR-0011](adr/0011-live-capture-guard-censor-and-attribute.md)).
- A watermark identifying the viewer: their full name with their **full** phone number beneath
  it and nothing else, jumping between the four corners and the exact centre of the class —
  the centre catches a camera zoomed in past the corners (docs/11 §9).
- Persian UI in the **Modam** font (FontIran; it replaced Peyda). The classroom was first built
  skeuomorphic; it now uses a **navy glass** theme in **dark and light** (docs/11 §11).

---

## Q&A from kickoff

### Q1 — How should the Windows/Android/iOS apps be built?

**Answer: Flutter.**

One Dart codebase targets Windows, Android and later iOS. Chosen over React+Tauri+Capacitor,
React Native+Electron and .NET MAUI because:

- The hard part of this product is native: background downloads, OS keystore access,
  screen-capture blocking, and in-memory decryption. Flutter reaches all of it through FFI
  and platform channels with one plugin layer, rather than three.
- Excellent RTL and Persian text shaping out of the box.
- A 2-person team cannot maintain two separate UI layers.

Cost accepted: Dart is a new language for the team, and the Windows video stack needs
`media_kit` rather than the first-party `video_player`.

### Q2 — What backend and database?

**Answer: NestJS + PostgreSQL.**

TypeScript end to end, so `packages/contracts` types are shared between API and tooling
without duplication. BullMQ gives the media pipeline a real job queue. Postgres holds
everything relational; Redis backs queues and short-lived state.

### Q3 — How strictly must video be protected?

**Answer (verbatim): "Both the class and the recorded videos are really really strict and
have to be protected. its the whole point of the application and project."**

Therefore: maximum protection achievable without a DRM vendor. Custom AES with a
self-hosted license server, all key handling in native Rust, behind a
`ContentProtectionProvider` interface so commercial DRM can be added later.

**Stated limit, acknowledged up front:** without Widevine L1 / PlayReady SL3000 / FairPlay,
a determined attacker with an HDMI capture card or a phone camera cannot be stopped.
SpotPlayer has the same ceiling. Strategy is defense in depth plus forensics — make
extraction cost far exceed content value, and make every leaked frame identify the account
it leaked from. Full detail in [03-content-protection.md](03-content-protection.md) and
[08-threat-model.md](08-threat-model.md).

### Q4 — Where is it hosted, and what services are reachable?

**Answer: self-hosted server + MinIO.**

Own hardware or VPS, MinIO for S3-compatible object storage, Docker Compose for deploys.
No dependency on services that are unreachable or unpayable from Iran. All object storage
access goes through an S3 client, so any S3-compatible provider (ArvanCloud, Liara) can
replace MinIO by changing environment variables only.

### Q5 — One repo or two?

**Answer: one monorepo with clear boundaries.**

`apps/`, `services/`, `packages/`, `infra/`. Each developer works inside their own folders,
so merge conflicts stay rare. `packages/contracts` is the shared seam and changes there go
through review.

### Q6 — What powers the live classroom?

**Answer: LiveKit, self-hosted.**

Open-source WebRTC SFU with a built-in **Egress** service that records a room composite
straight to S3/MinIO — exactly the handoff the video library needs. Has a Flutter SDK,
handles screen share and data channels for the whiteboard, and scales to large rooms.

### Q7 — How do students sign in?

**Answer: phone number + SMS OTP.**

Standard in Iran, no password resets, and the phone number is a strong identity anchor for
device binding and watermarking. SMS sits behind a `SmsProvider` interface: a console driver
in development, Kavenegar/SMS.ir in production.

### Q8 — What is in the phase-1 scope?

**Answer: three of four offered items.**

- Library: courses, sessions, Persian search, watch progress and resume
- Protected online playback
- Offline download + licensing

Deferred to M5: chapters, attachments, notes, quizzes. Their tables are created now so the
schema does not churn later.

---

## Assumptions made without asking

Reversible defaults. Raise any of these and they change.

| # | Assumption |
|---|---|
| A1 | UI is Persian-first and RTL, with i18n scaffolding so English can be added later. |
| A2 | Jalali (Shamsi) dates everywhere user-facing; UTC in the database, always. |
| A3 | No admin web panel in phase 1 — managed via the API, a seed script and an admin CLI. Panel is M6. |
| A4 | Screen-capture blocking is on by default, with a per-course override flag, since it can break accessibility tools and some remote-support software. |
| A5 | Phone numbers are stored in E.164 (`+98...`) and displayed locally (`09...`). |
| A6 | A student's enrollment, not a purchase, grants access. Payments are out of scope until M7. |
| A7 | One institute per deployment. No multi-tenancy in the schema. |

---

## Non-functional targets

Deliberately modest — these are starting targets to measure against, not promises.

| Concern | Target |
|---|---|
| Live class size | 100 participants per room, 1 presenter + screen share |
| Concurrent VOD viewers | 300 on one server before horizontal scaling is needed |
| Recording availability | A finished class is playable within 30 min of ending |
| Offline license window | 30 days default, per-course configurable |
| API p95 latency | < 300 ms for catalog reads |
| Player cold start to first frame | < 3 s online, < 1 s offline |
