# Data Model

**Source of truth: `services/api/prisma/schema.prisma`.** This document explains the
*reasoning* — why tables exist and why they are shaped the way they are. When they disagree,
the schema wins and this file needs updating.

IDs are ULIDs with a type prefix (`usr_`, `crs_`, `vid_`) — sortable by creation time, and a
mis-passed id is obvious in a log line.

All timestamps are `timestamptz` in **UTC**. Jalali conversion happens in the client only.

---

## Identity

**`users`** — `phone` (E.164, unique) is the identity anchor; no password column at all in
phase 1. `display_name`, `role` (`student` / `teacher` / `admin`), `status`
(`active` / `suspended`), `revocation_epoch` (int, incremented to kill every licence the user
holds — see [03-content-protection.md](03-content-protection.md)).

**`otp_codes`** — `code_hash` (never the plaintext), `expires_at`, `consumed_at`,
`attempt_count`, `ip`. Rows are kept after consumption for abuse analysis.
Rate limiting reads this table: N per phone per hour, M per IP per hour.

**`devices`** — the foundation of offline protection. `fingerprint_hash` (derived on-device
from stable hardware identifiers), `platform`, `name` ("لپ‌تاپ حسن"), `public_key` (X25519, the
device's half of the key exchange), `trusted_at`, `revoked_at`, `last_seen_at`.
Content keys are wrapped for a row in this table, never for a user.

**`refresh_tokens`** — rotating, single-use, bound to a `device_id`. `used_at` set on
consumption; a second use of a consumed token revokes the device session, because that is a
theft signal rather than a race.

---

## Catalog

```
terms ──► courses ──► course_sections ──► videos
                └──► enrollments ──► users
```

**`terms`** — academic term ("نیمسال اول ۱۴۰۵"). Simplifies archiving a whole year later.

**`courses`** — `title`, `slug`, `description`, `teacher_id`, `cover_key`, `status`
(`draft`/`published`/`archived`), plus protection policy fields that belong to the course
rather than the video: `allow_download`, `allow_capture`, `offline_window_days`,
`max_devices`, `max_concurrent_streams`. Policy lives here so an admin changes it in one place
and every video inherits it.

**`course_sections`** — weeks or chapters within a course. Ordering column, not sorted by
creation.

**`videos`** — one row per playable item, whether it came from a live class or was uploaded
directly. Key columns: `source` (`live_recording`/`upload`), `recording_id` (nullable link back
to the class), `duration_ms`, `status` (`processing`/`pending_review`/`ready`/`failed`),
`published_at`, `unlock_rule` (JSON — the M5 quiz gate, e.g. "requires passing quiz X"),
`search_text` (generated, normalized — see below).

**`enrollments`** — `user_id` × `course_id`, `status`, `enrolled_at`, `expires_at`. Access is
checked here on every playback request. A unique constraint on the pair prevents double
enrollment.

---

## Media

**`video_assets`** — one row per rendition (`1080p`, `720p`, `480p`, `audio`). Holds
`storage_key`, `width`, `height`, `bitrate`, `codec`, `segment_count`, `byte_size`. Separate
from `videos` because renditions are produced independently and can be re-encoded or deleted
without touching the logical video.

**`content_keys`** — the CEK, stored as `wrapped_key` (encrypted with the KEK) plus
`key_version` and `algorithm`. Deliberately its own table rather than a column on `videos`:
different access rules, different audit needs, and key rotation wants history. A leaked
database dump yields wrapped keys only.

**`recordings`** — the live↔VOD seam. `class_id`, `session_id`, `course_id`, `egress_id`
(unique — this is what makes webhook retries idempotent), `raw_storage_key`, `status`,
`error`, `video_id` (set once packaging succeeds), `metadata` (the raw `metadata.json`, kept
verbatim so a filing mistake can be reconstructed).

---

## Licensing and offline

**`licenses`** — the issued blob and its terms: `user_id`, `scope` (JSON course/video ids),
`not_before`, `not_after`, `max_devices`, `offline_window_days`, `revocation_epoch`,
`signed_blob` (the exact bytes the client verifies), `revoked_at`, `revoked_reason`.
Storing the signed blob rather than regenerating it means the server can always show exactly
what a client was given.

**`license_devices`** — which devices a licence is bound to. Its own table so the device
allowance can be enforced with a count and a device can be released without reissuing.

**`downloads`** — `user_id`, `device_id`, `video_id`, `state`
(`queued`/`downloading`/`complete`/`expired`/`deleted`), `bytes_downloaded`, `expires_at`.
The server knows what is sitting on which device, which is what makes remote expiry and
"you have this on 2 of 2 devices" possible.

---

## Watching

**`watch_progress`** — one row per `(user, video)`: `position_ms`, `completed`,
`updated_at`. This is the resume point. Small, frequently updated, read on every video open.

**`watch_events`** — append-only: `user_id`, `device_id`, `video_id`, `event`
(`start`/`heartbeat`/`seek`/`pause`/`complete`), `position_ms`, `created_at`, `ip`.

Two tables instead of one because they have opposite shapes. `watch_progress` is a tiny
mutable row read on every open; `watch_events` is a large immutable log that is only ever
appended and aggregated. It feeds:

- SpotPlayer-style statistics — how many times, how long, how far each student got
- Abuse detection — one account watching from three cities at once
- Course quality signals — where students consistently stop or rewind

It grows fast. Partition by month from M2, and aggregate into rollup tables rather than
querying it live in the admin panel.

---

## Phase-2 tables (created now, unused until M5)

Created in the first migration so the schema does not churn later:

**`chapters`** — `video_id`, `title`, `start_ms`, `order`. SpotPlayer's "timed titles".
**`attachments`** — `video_id` or `course_id`, `name`, `mime`, `storage_key`, `copyable`
(false means it renders in-app but cannot be exported — the flag SpotPlayer exposes).
**`notes`** — student bookmarks: `user_id`, `video_id`, `position_ms`, `body`.
**`quizzes`**, **`quiz_questions`**, **`quiz_attempts`** — the gate referenced by
`videos.unlock_rule`.

---

## Persian search

PostgreSQL ships no Persian stemmer, and Persian text has several traps: Arabic vs Persian
letter forms (`ك`/`ک`, `ي`/`ی`), the zero-width non-joiner inside compound words, optional
diacritics, and Arabic-Indic vs Western digits. A naive `LIKE` or `to_tsvector('simple')`
misses obvious matches.

Approach:

1. A SQL function `normalize_fa(text)` folds letter variants, strips ZWNJ and diacritics, and
   converts digits to Western.
2. `videos.search_text` and `courses.search_text` are generated columns holding
   `normalize_fa(title || ' ' || description)`.
3. A GIN index with `pg_trgm` over `search_text` gives fuzzy and substring matching, which
   handles the stemming gap acceptably for course titles and lecture names.
4. Queries are normalized the same way before matching, so the transformation is symmetric.

If relevance proves weak on real data (see Q7 in [10-open-questions.md](10-open-questions.md)),
Meilisearch has strong Persian support and drops in behind the same `SearchService` interface —
which is why that interface exists from day one.
