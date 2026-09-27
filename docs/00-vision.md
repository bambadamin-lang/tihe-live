# TIHE Live — Vision

## What we are building

A two-part platform for an educational institute:

1. **Live virtual classroom** — real-time classes with video, audio, screen share, chat and
   a whiteboard. The reference point is Adobe Connect: a teacher-led room with roles,
   permissions and layouts, not a symmetric video call.
2. **Protected video library** — every live class is recorded automatically, processed, and
   published into a course library that students watch on Windows and Android (iOS later),
   online or fully offline. The reference point is
   [SpotPlayer](https://spotplayer.ir/features).

The two halves are one product: a class ends, and minutes later it is a searchable,
protected, resumable video in the student's library with no human intervention.

## Who uses it

| Role | What they do |
|---|---|
| **Student** | Joins live classes. Watches recordings online or downloads them for offline study. Resumes where they left off. Reads attached materials, takes notes, answers quizzes. |
| **Teacher** | Runs the live class. Reviews and publishes the recording, adds chapters, materials and quizzes. Sees who watched what. |
| **Admin / institute staff** | Creates terms, courses and enrollments. Issues and revokes licenses. Investigates leaks. Reads watch statistics. |

## Why it must be protected

The institute's recorded courses are the asset being sold or granted. If a recording can be
pulled out of the app and passed around, the business reason for the platform disappears.
This is the same problem SpotPlayer solves, and the reason institutes in Iran pay for it
rather than uploading to a normal video host.

So content protection is treated as a **product requirement**, not a hardening task bolted
on at the end. It shapes the data model, the API, the player and the build pipeline. See
[03-content-protection.md](03-content-protection.md) and
[08-threat-model.md](08-threat-model.md).

## What we match from SpotPlayer

These are the capabilities that make SpotPlayer worth copying, and our equivalent:

| SpotPlayer capability | Our plan |
|---|---|
| Offline playback after license activation | `.tihex` encrypted container + device-bound Ed25519 license |
| License revocable at any time | `licenses.revoked_at` + revocation epoch honoured on heartbeat |
| Device permission limits | `devices` table, per-license device allowance |
| Up to three per-user watermarks | Native-layer moving overlay carrying account identity |
| Timed titles per video | `chapters` table, seekable chapter list in the player |
| HTML and PDF materials, protected or copyable | `attachments` table with a `copyable` flag |
| Quizzes between videos, gating the next one | `quizzes` + `quiz_attempts`, `videos.unlock_rule` |
| Simultaneous download and playback | Progressive segment download, play while fetching |
| Statistics: license state, watch times and counts | `watch_events` append-only log → analytics views |
| JSON API to issue and modify licenses | `POST /licenses/issue`, `/licenses/:id/revoke` |
| Windows, Android (and Mac/iOS) | Flutter: Windows, macOS, Android and iOS ([ADR-0009](adr/0009-four-platforms-classroom-desktop-first.md)) |

## What we deliberately do not build

Saying no now keeps the project finishable by two people:

- **Our own SFU.** LiveKit is self-hosted and handles the media plane.
- **Our own codecs or container format for streaming.** Standard HLS, encrypted. Only the
  offline container (`.tihex`) is custom, and only because it has to be.
- **Commercial DRM.** Widevine/PlayReady/FairPlay need a vendor relationship. The
  protection layer is designed so they can be added later (M7) without a rewrite.
- **A general-purpose LMS.** No forums, no gradebook, no assignment submission in phase 1.
- **Web playback.** The browser cannot hold a key safely. Protected content plays in the
  app only. A marketing/catalogue website is fine; playback is not.
- **Live streaming to the public.** Classes are enrolled-students-only, always.

## Definition of done for phase 1

A student on Windows or Android can:

1. Sign in with their phone number and an SMS code.
2. See the courses they are enrolled in, and search inside them in Persian.
3. Play a recorded session, with the video encrypted end to end and their identity
   watermarked on screen, and resume it later from the same second on another device.
4. Download that session for offline viewing, watch it with no network, and have their
   progress sync when they reconnect.
5. Lose access the moment an admin revokes their license.
