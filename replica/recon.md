# Recon map: Adobe Connect + SpotPlayer → one TIHE app (Windows, macOS, Android, iOS)

Scope: the student and admin side of two products in one app. Live classes in the style of
Adobe Connect (meeting rooms with roles, pods, layouts, whiteboard, hands). A protected course
library in the style of SpotPlayer (encrypted video, device-limited licences, watermark,
recording blocked). One sign-in, then a dashboard that leads to either.
For: TIHE, an educational institute, for its own students and teachers.
Date: 2026-10-04

Rules followed (replica-recon): public sources and the institute's own requirements only. No
code, assets, copy, logos or names from either product. Neither name appears anywhere in the
app's user interface; the product is TIHE throughout.

## Sources

| # | source | URL | notes |
| --- | --- | --- | --- |
| 1 | Adobe Connect help: meeting room basics | https://helpx.adobe.com/adobe-connect/using/meeting-basics.html | stage, pods, layouts, menu bar, three roles, presenter-only area |
| 2 | Adobe Connect help: attendees pod | https://helpx.adobe.com/adobe-connect/using/attendees-pod.html | roles and permissions, raise hand ordering, status, breakout rooms |
| 3 | Adobe Connect help: participating in sessions | https://helpx.adobe.com/adobe-connect/using/participating-training-sessions-meetings.html | attending, recordings, whiteboard |
| 4 | University of Waterloo KB: meeting functions in depth | https://uwaterloo.atlassian.net/wiki/spaces/ISTKB/pages/270565553 | a teaching institution's view of the same features |
| 5 | SpotPlayer licence API (third-party PHP client docs) | https://packagist.org/packages/abdal/spotplayer-php | licence fields: courses, watermark, offline days, devices per platform, concurrent use, test mode |
| 6 | SpotPlayer licence by SMS (WordPress plugin) | https://www.melipayamak.com/lab/sms-spotplayer-plugin/ | the licence-key-per-purchase flow |
| 7 | TIHE requirements and decisions | [docs/01-requirements.md](../docs/01-requirements.md) | protection is the product; four platforms; Peyda; glass theme |
| 8 | TIHE live classroom design | [docs/11-live-classroom.md](../docs/11-live-classroom.md) | the classroom recon already done for the live side |
| 9 | The institute's new requirements (2026-10-04) | this PR | phone + password, N devices at once set by an admin, one app with a dashboard, recording ends the session |

## Core loop

A student signs in once with phone and password, picks **live class** or **library** on the
dashboard, and watches. Nobody can record it, and every frame names the viewer.

## Screens

| ID | screen | how to reach | purpose | key components | states |
| --- | --- | --- | --- | --- | --- |
| S01 | Sign in | app start, signed out | phone + password | phone field (Persian digits accepted), password field with show/hide, primary button | empty, typing, wrong password, locked out, offline, server unreachable |
| S02 | Device limit | S01 when N devices are already signed in | sign one out and continue | device rows (name, platform, last seen), "sign out and continue" | list, signing out, error |
| S03 | Dashboard | after sign in | choose live classes or library | two large glass cards, greeting, account button, update banner | loading, no classes today, no courses, admin card (admins only) |
| S04 | Live classes | S03 → live | classes live now and coming up | class rows with live badge, join button, start button (teachers) | empty, live now, upcoming, error |
| S05 | Classroom | S04 → join | the live class | stage, pods, whiteboard, hands, chat, layouts, watermark (existing tihe_classroom) | joining, live, reconnecting, ended |
| S06 | Recording detected | during S05 or S10 | censor at once | censor screen, countdown, what to close | censored, recorder closed (recovers) |
| S07 | Removed for recording | S06 after the grace period | end the session | message, rejoin button | rejoin blocked while the recorder runs |
| S08 | Library | S03 → library | enrolled courses | course rows, search | loading (skeletons), empty, error |
| S09 | Course | S08 → course | sections and videos | section headers, video rows with progress | loading, empty section, error |
| S10 | Player | S09 → video | protected playback | video surface, controls, watermark, chapters | loading, playing, paused, error, censored |
| S11 | Account | S03 → account | name, devices, password, sign out | device list, change password, sign out | |
| S12 | Change password | S11 | current + new password | two fields, strength hint | wrong current, too short, done |
| S13 | Admin: users | S03 admin card | find and create users | search by phone, user rows, add user | empty, results |
| S14 | Admin: user | S13 → user | edit one user | name, role, status, device limit (default or custom), reset password, signed-in devices, enrollments | |
| S15 | Admin: settings | S13 | institute defaults | default device limit | saving, saved |
| S16 | Updating | update banner | install a new version | progress, "app restarts" | downloading, installing, failed |

## Flows

```
F01 Student signs in
    S01 -> S03
    happy path clicks: 1 (type phone, type password, press enter)
    edge: Persian digits, +98 / 0098 / 9xx forms, wrong password, account suspended, offline

F02 Student signs in with N devices already signed in
    S01 -> S02 -> S03
    happy path clicks: 2 (pick a device, confirm)
    edge: the device picked is this one re-installed, the limit lowered by an admin meanwhile

F03 Student joins a live class
    S03 -> S04 -> S05
    happy path clicks: 2
    edge: class not started, not enrolled, LiveKit unreachable, second device joins (replaces)

F04 Student starts a screen recorder in class
    S05 -> S06 -> (closes recorder) S05
    S05 -> S06 -> (10 s pass) S07 -> (closes recorder) S04 -> S05
    edge: recorder already open before joining, recorder that the OS reports (Android, iOS),
          recorder found by process name (Windows, macOS), Remote Desktop, mirrored display

F05 Student watches a protected video
    S03 -> S08 -> S09 -> S10
    happy path clicks: 3
    edge: not enrolled (never listed), licence expired, device signed out remotely mid-video

F06 Student starts a recorder during a video
    S10 -> S06 (playback paused, picture hidden) -> (closes) S10, or (10 s) stopped with message

F07 Admin sets the device limit
    S03 -> S13 -> S15 (default N) or S13 -> S14 (this user's N)
    edge: lowering N below what is signed in (existing sessions stay; the next sign-in is refused)

F08 Admin adds a student
    S13 -> add user (phone, name, password) -> S14 -> enroll in a course

F09 App updates itself
    S03 banner -> S16 -> app restarts on the new version

F10 Teacher starts a class
    S03 -> S04 -> start -> S05 as host
```

## Components

| component | variants | states | used on |
| --- | --- | --- | --- |
| Glass card | large (dashboard), section, row | default, hover, pressed, focus, disabled | all |
| Button | filled, tonal, text, danger | default, hover, focus, disabled, loading | all |
| Text field | phone (LTR digits), password (show/hide), search | empty, focus, error | S01, S12, S13 |
| Device row | this device, other device | default, signing out | S02, S11, S14 |
| Banner | info (update), danger (failure) | with progress, with actions | S03, S16 |
| Censor screen | class, video | countdown, removed | S06, S07 |
| Watermark | class corner hop, video drift | always on | S05, S10 |
| Skeleton list | rows | loading | S04, S08, S09 |

## Inferred data model

```
Meeting room / class   id, course, title, host, schedule, live state, layout, recording
                       evidence: sources 1, 2; docs/11
                       confidence: high (already built in services/live)

Role in a room         host | presenter | participant, plus per-person extra rights
                       evidence: sources 1, 2
                       confidence: high (services/live capabilities)

Licence                user, courses, watermark text, offline days, devices per platform,
                       concurrent devices, test mode
                       evidence: source 5
                       confidence: medium (third-party client docs, not the vendor's)

Device                 per user, platform, name, last seen, signed in or not
                       evidence: source 5 ("limit access per platform", "concurrent connections");
                       the institute's requirement "only N devices can log in at once"
                       confidence: high for the requirement, medium for the original's semantics

Account                phone, password (new: replaces SMS codes), role, status, device limit
                       (admin-set, per user, with an institute default)
                       evidence: source 9
                       confidence: high
```

Relationships: User 1-n Device, User n-n Course (Enrollment), Course 1-n Video, Course 1-n Class
(services/live), Video 1-n ContentKey, User 1-n Licence.

## Feature matrix

See `features.csv`. Must: 32, should: 10, could: 4, skip: 6 (52 rows; 10 are TIHE's own
requirements, marked `original=no`, which parity leaves out). Baseline parity: 48.4.

## Out of scope (cannot or should not be cloned)

- Both products' names, logos, icons, colours, copy and installers. TIHE has its own glass theme
  and the Peyda font.
- Adobe Connect's breakout rooms, polls and Q&A: deferred by the institute (docs/10, Q6).
- Adobe Connect's web/browser client: protected playback in a browser needs commercial DRM
  (docs/10, Q2).
- SpotPlayer's licence-key sale flow (WordPress, payment gateways): enrollment, not purchase,
  grants access (A6).
- Either product's DRM internals. TIHE's protection is its own design (docs/03, ADR-0003).
- Hardware-level protection (HDMI capture, a camera at the screen): no software stops it; the
  watermark makes such copies attributable (docs/08, T3).

## Size

Screens 16, flows 10, entities 5 (on top of the existing schema). Hard parts: protected
playback without commercial DRM (the Rust core, a loopback server, a video engine on four
platforms), real-time classes (LiveKit, already built), concurrent device sessions, recording
detection across four operating systems. Size: **XL — rescoped**. This PR delivers the vertical
slice (sign in, device limit, dashboard, live classes, library, recording policy, installer and
updates, admin) and records what remains in `build-log.md` and `parity.md`.
