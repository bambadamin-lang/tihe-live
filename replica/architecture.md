# Architecture: one TIHE app for live classes and the protected library

Reads [recon.md](recon.md) and [features.csv](features.csv). The stack is the one the repo
already has (replica-architect: "use what the user already knows"), so this file is about what
changes to deliver the recon's slice. The full system design stays in
[docs/02-architecture.md](../docs/02-architecture.md); the protection design in
[docs/03-content-protection.md](../docs/03-content-protection.md).

## Stack

| layer | choice | why |
| --- | --- | --- |
| app | Flutter, one app in `apps/player` for all four platforms | the player already has auth, routing (go_router), state (Riverpod) and a design system; the classroom is a package it imports |
| live classes | `packages/tihe_classroom` + `services/live` + LiveKit | already built (docs/11) |
| protection | `packages/secure-core` (Rust) + `packages/capture_guard` | no secret in Dart; one capture policy for class and video |
| API | NestJS + Prisma + Postgres (`services/api`, `packages/db`) | already built (#1) |
| storage | S3-compatible: RustFS on a PC or server | MinIO no longer publishes images; the code only uses an S3 client |
| server for now | Docker Compose on one PC (`infra/docker/compose.server.yml`) | the institute has no server yet; the same file runs on a VPS later |
| distribution | GitHub Releases: installer + `latest.json` in a public releases repo | the app updates itself without a token (PR #5) |

GitHub is not the server. It cannot accept writes from the app (so it cannot count signed-in
devices), cannot stream a class, and using it as an API or a video host breaks its terms. The
institute chose to run the real server on a PC until it rents one.

## Accounts: phone and password

Replaces SMS codes (ADR-0007, superseded by ADR-0013).

- **Who creates accounts.** An admin, in the app (S13–S14) or with the CLI. There is no public
  sign-up: enrollment, not purchase, grants access (A6).
- **Passwords.** Argon2id with a server-side pepper (`PASSWORD_PEPPER`), at least 8 characters.
  An admin-set password is marked `must_change_password`, so the student picks their own at
  first sign-in. There is no SMS reset: an admin sets a new temporary password.
- **No enumeration.** Unknown phone and wrong password give the same `INVALID_CREDENTIALS` after
  the same work: a dummy Argon2 verify runs when the phone is unknown.
- **Rate limits.** `login_attempts` (phone, ip, succeeded, created_at): 10 failures per phone
  per 15 minutes and 50 per IP, then `LOGIN_RATE_LIMITED` with `retryAfterSeconds`. Rows stay
  for abuse analysis, like `otp_codes` did.

## Devices: N signed in at once

The requirement is "only N devices can log in at once", so the limit counts **signed-in**
devices, not every device ever registered.

- A device is **signed in** while it holds a live refresh token: unused, unrevoked and
  unexpired. Signing out revokes it and frees the slot. A device left alone for the refresh
  lifetime (30 days) times out and frees its slot by itself.
- **N** is the user's own limit if an admin set one (`users.max_devices`), else the institute
  default (`settings.default_max_devices`, editable by admins), else `DEFAULT_MAX_DEVICES`.
- **At the limit**, sign-in fails with `DEVICE_LIMIT_REACHED`, listing the signed-in devices
  (name, platform, last seen) and a 5-minute single-purpose ticket. The student picks one and
  `POST /auth/login/replace` signs it out and finishes signing in, with no second password
  entry (F02).
- **Signing a device out** (from that device, from another device, or by an admin) also expires
  its offline downloads and ends its playback sessions. Otherwise sign out, sign in elsewhere,
  and keep watching offline would beat the limit. An offline device learns of it at its next
  contact, bounded by the offline window (docs/03, Layer 5).
- Lowering N does not sign anyone out; it applies to the next sign-in.

## Schema changes (migration `password_sign_in_and_device_sessions`)

```sql
alter table users
  add column password_hash text,                     -- argon2id, peppered; null = cannot sign in
  add column password_changed_at timestamptz,
  add column must_change_password boolean not null default false,
  add column max_devices integer check (max_devices between 1 and 20);  -- null = default

create table settings (
  key text primary key,                              -- 'default_max_devices'
  value jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by text references users(id) on delete set null
);

create table login_attempts (
  id text primary key,
  phone text not null,                               -- E.164
  ip text,
  succeeded boolean not null,
  created_at timestamptz not null default now()
);
create index on login_attempts (phone, created_at);
create index on login_attempts (ip, created_at);

drop table otp_codes;
```

## API

| method path | does | who | flow |
| --- | --- | --- | --- |
| POST /auth/login | phone + password + device → session, or DEVICE_LIMIT_REACHED with devices and a ticket | anyone | F01, F02 |
| POST /auth/login/replace | ticket + device to sign out → session | the ticket's holder | F02 |
| POST /auth/password | current + new password | signed in | S12 |
| POST /auth/refresh, POST /auth/logout, GET /auth/me | unchanged; logout now frees the slot | signed in | |
| GET /devices, DELETE /devices/:id | list, sign out one of your devices | signed in | S11 |
| GET/PATCH /admin/settings | default device limit | admin | F07 |
| GET/POST /admin/users, GET/PATCH /admin/users/:id | find, create, edit (name, role, status, limit, password) | admin | F07, F08 |
| GET/DELETE /admin/users/:id/devices[/:deviceId] | see and sign out a user's devices | admin | |
| POST/DELETE /admin/users/:id/enrollments[/:courseId] | enroll or remove | admin | F08 |
| GET /admin/courses | courses to enroll in | admin | F08 |
| GET /internal/courses/:id, /internal/enrollments/check, /internal/users/:id/profile | the directory services/live calls (contract: packages/contracts/src/live/directory.ts) | services/live (`X-Internal-Token`) | F03 |

**Access tokens** gain `role`, `iss: tihe-api` and `aud: tihe`, the claims services/live
already requires (`accessTokenClaimsSchema`). Without them every API-issued token was refused
by the classroom: the two services had never been run together.

## Recording policy: censor, then end (ADR-0011 amended)

| t | class (S05) | video (S10) |
| --- | --- | --- |
| recorder detected | censor screen, remote audio muted, host alerted | picture hidden, playback paused |
| recorder closed within 10 s | class returns | playback can resume |
| still recording at 10 s | student leaves the session: S07 "removed for recording" | playback session ends: "playback stopped" |
| rejoin | allowed once no recorder is detected | same |

A pure-Dart state machine in `capture_guard` (`CaptureEnforcer`), unit-tested with fake time,
so both surfaces enforce the same rule. The host's alert says the student was removed.

## The app (apps/player becomes the one app)

```
/sign-in                     S01   phone + password
/sign-in/devices             S02   device limit
/                            S03   dashboard: live classes · library · admin (admins)
/live                        S04   classes
/live/:sessionId             S05   classroom (tihe_classroom's ClassroomPage)
/library, /course/:id        S08, S09
/watch/:id                   S10   player (full-bleed)
/account, /account/password  S11, S12
/admin, /admin/users/:id     S13, S14, S15
```

- Theme: the classroom's glass theme (light and dark, `ClassroomTheme`) for every screen, with
  Modam registered at start-up.
- Server address: one setting (the installer writes it; the sign-in screen can change it).
  The API is at `/v1`, the classroom at `/v1/live`, so one address serves both behind the
  Compose stack's gateway.
- Demo mode: "try without a server" on S01 opens the dashboard with the in-process demo class.
  The library needs a server, since protected playback has no offline demo path.

## The server on one PC

`infra/docker/compose.server.yml` builds and runs everything: Postgres, Redis, RustFS, the API,
services/live, the media worker, LiveKit (and Egress), behind one Caddy gateway on port 8080
(`/v1` → API, `/v1/live` → services/live, `/storage` → RustFS for presigned media).
`infra/scripts/server-setup.sh` generates secrets once and creates the first admin.

## Build order

1. Vertical slice: password sign-in, the token claims fix, the internal directory, and the app's
   sign-in → dashboard → live class with a real services/live.
2. Device sessions and the S02 flow; admin settings and users.
3. Library and player screens in the glass theme; protected playback through secure-core.
4. Recording policy in class and player.
5. Installer and updater for the one app; the Compose server.

## Riskiest parts

- Protected playback on four platforms: Rust compiled per platform, FFI, the loopback server
  feeding media_kit. Nothing plays until all three work.
- Device-session counting under races: two devices signing in at the same moment at N-1.
  Handled with a per-user transaction lock (`select … for update` on the user row).
- Recorder detection false positives: a student with OBS merely open is removed after 10 s. That
  is the institute's rule (it matches the original's behaviour); the message says what to close.
