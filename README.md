<div dir="rtl">

# تیهه لایو (TIHE Live)

سامانه کلاس مجازی و کتابخانه ویدیوی محافظت‌شده برای مؤسسه آموزشی.

کلاس‌ها به صورت زنده برگزار می‌شوند، خودکار ضبط می‌شوند، و چند دقیقه بعد در قالب ویدیوی
رمزنگاری‌شده در کتابخانه دانشجو قرار می‌گیرند — قابل تماشا به صورت آنلاین یا آفلاین، روی
ویندوز و اندروید (و در آینده iOS).

**حفاظت از محتوا هدف اصلی پروژه است، نه یک ویژگی جانبی.**

</div>

---

# TIHE Live

A virtual classroom and protected video library for an educational institute.

Classes run live, are recorded automatically, and appear minutes later as encrypted videos in
each student's library — watchable online or fully offline, on Windows, macOS, Android and iOS.

Reference points: **Adobe Connect** for the live classroom, **[SpotPlayer](https://spotplayer.ir)**
for the protected video library.

**Content protection is the point of the project, not a feature of it.**

## Quick start

Requires Node 22+, pnpm 10+, Docker, and Rust 1.80+ (Flutter 3.35+ only for the client).

```bash
pnpm install

# Postgres + Redis + S3 storage, with buckets created
docker compose -f infra/docker/compose.dev.yml up -d

# generate local dev secrets (KEK + licence signing keypair) into .env
./infra/scripts/generate-secrets.sh

cp .env.example .env                              # then fill from the output above
pnpm --filter @tihe/db migrate
pnpm --filter @tihe/db seed
pnpm --filter @tihe/api start:dev                 # http://localhost:3000/docs
```

Then walk the whole student flow in one command:

```bash
./infra/scripts/smoke-test.sh 09125550003
```

It signs in as the seeded student, lists courses, searches in Persian, updates progress, syncs an
offline event batch, and checks that playback is refused without a licence — 25 assertions, each
printed as it passes.

The Rust protection core is independent of all of the above:

```bash
cargo test --manifest-path packages/secure-core/Cargo.toml
```

The Flutter client needs the Flutter SDK and a platform toolchain:

```bash
cd apps/player && flutter pub get && flutter run -d windows   # or -d android
```

## Layout

```
apps/player/            Flutter app shell (Windows, macOS, Android, iOS)
services/api/           NestJS: auth, catalog, progress, licensing, webhooks
services/media-worker/  ffmpeg: transcode, encrypt, package HLS
services/ingest-worker/ live recording → VOD library
services/live/          live classroom: classes, LiveKit, classroom gateway, recording template
packages/tihe_classroom/ Flutter: the live classroom UI (Persian, glass, light and dark)
packages/capture_guard/ Flutter plugin: block and detect screen capture
packages/contracts/     shared zod schemas + OpenAPI — the API contract
packages/secure-core/   Rust: licences, crypto, .tihex container, loopback HLS server
infra/                  Docker Compose, nginx, helper scripts
docs/                   architecture, protection design, threat model, roadmap, ADRs
```

## Documentation

Start with [`docs/00-vision.md`](docs/00-vision.md), then:

| Document | What it covers |
|---|---|
| [01-requirements.md](docs/01-requirements.md) | Every locked decision, and the Q&A behind it |
| [02-architecture.md](docs/02-architecture.md) | Services, ownership, data flows |
| [03-content-protection.md](docs/03-content-protection.md) | The eight protection layers, in implementable detail |
| [04-roadmap.md](docs/04-roadmap.md) | Milestones M0–M7 |
| [05-api-contracts.md](docs/05-api-contracts.md) | API surface and error codes |
| [06-recording-pipeline.md](docs/06-recording-pipeline.md) | The live↔VOD contract |
| [07-data-model.md](docs/07-data-model.md) | Why each table exists |
| [08-threat-model.md](docs/08-threat-model.md) | **What the protection actually stops, and what it does not** |
| [09-team-workflow.md](docs/09-team-workflow.md) | Branches, ownership, definition of done |
| [10-open-questions.md](docs/10-open-questions.md) | Deferred decisions, with deadlines |
| [11-live-classroom.md](docs/11-live-classroom.md) | The live classroom: roles, hands, layouts, whiteboard, capture censoring, watermark |
| [adr/](docs/adr/) | Decision records |

## Status

**M0 — foundation.** Monorepo, documentation, infrastructure, shared contracts, API with the
full data model, Rust protection core, Flutter shell. See
[the roadmap](docs/04-roadmap.md) for what comes next.
