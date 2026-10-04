# Open Questions

Decisions deliberately deferred. Each one has a "decide by" milestone so it does not rot.

| # | Question | Why deferred | Decide by |
|---|---|---|---|
| Q1 | Do students pay directly, or does the institute enroll them? | No payment requirement stated; enrollment covers phase 1. Affects whether ZarinPal and an order/invoice model are needed. | M5 |
| Q2 | Is there a browser-based viewing option for students without Windows/Android? | Protected playback in a browser is not achievable without commercial DRM. May need a deliberately lower-quality or preview-only web path. | M6 |
| Q3 | How many devices per student? Default is 2 with `maxDevices` configurable. | Needs a real policy from the institute — too low generates support load, too high enables sharing. | M4 |
| Q4 | Retention: how long do recordings stay? Do old terms get archived to cold storage? | Storage cost is unknown until real class lengths and counts are measured. | M2 |
| Q5 | Does a teacher review and approve a recording before students see it, or is publishing automatic? | Affects whether `videos.status` needs a `pending_review` state in the default flow (the state exists; the default is what is undecided). | M2 |
| ~~Q6~~ | ~~Does the live class need a whiteboard, breakout rooms, polls, or hand-raising in phase 1?~~ **Resolved:** whiteboard, hand-raising, roles/permissions, layouts and capture censoring are in scope; breakout rooms and polls are not. See [11-live-classroom.md](11-live-classroom.md). | — | — |
| Q7 | Persian search: is `pg_trgm` good enough, or do we need Meilisearch? | Cannot be judged without real course titles and descriptions. `SearchService` is an interface so either works. | M1 |
| Q8 | Where do KEK and the licence signing key live in production — environment file, or Vault? | Compose uses env vars for development. A single-server deployment may not justify Vault. | M3 |
| Q9 | Backup and disaster recovery: what is the RPO for Postgres and for MinIO? | Needs the institute's answer on acceptable data loss. | M2 |
| ~~Q10~~ | ~~Do we need Mac support?~~ **Resolved:** yes — Windows, macOS, Android and iOS are all targets; the classroom ships desktop-first. See [ADR-0009](adr/0009-four-platforms-classroom-desktop-first.md). | — | — |
| Q12 | Screen-share audio: which teachers need to play clips with sound, and is a virtual audio cable acceptable until a native loopback plugin exists? | Native `livekit_client` captures no system audio with a screen share. | L3 |
| Q13 | Should egress support multi-part recordings (`composite-partN.mp4` + `parts[]` in `metadata.json`) so a crashed egress can resume? | Contract change with the video pipeline; v1 records one continuous file. | M2 |
| Q11 | Are class recordings ever shared between courses or terms (e.g. a reused lecture)? | Affects whether `videos` needs a many-to-many with `course_sections` instead of the current one-to-many. | M1 |
| Q12 | What is the product actually called? `TihePlayer` is a placeholder. | Naming was deferred to get the protected-content pipeline moving. It is cheap to change now and expensive later: the `.tihex` file extension and the `tihe_player` package id are deliberately *not* renamed yet, because students will have `.tihex` files on disk and an extension should change exactly once. | Before the first build handed to students |
