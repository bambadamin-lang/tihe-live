# API Surface

**Source of truth: `packages/contracts` (zod schemas) and the OpenAPI document served at
`/docs-json`.** This file is the map, not the specification.

Base URL: `/v1`. All requests and responses are JSON. All errors share one envelope.

## Conventions

**Auth.** `Authorization: Bearer <access token>` on everything except `/health`, `/auth/*`
and `/webhooks/*`. Access tokens last 15 minutes and are bound to a device id; refresh tokens
last 30 days, are single-use and rotate.

**Error envelope** — one shape for every failure, so the client has one code path:

```jsonc
{
  "error": {
    "code": "LICENSE_EXPIRED",          // stable, machine-readable, never localised
    "message": "License expired at 2026-10-27T00:00:00Z",   // English, for logs
    "messageFa": "اعتبار دسترسی شما به پایان رسیده است",     // shown to the user
    "details": { "licenseId": "lic_01J..." },
    "requestId": "req_01J..."
  }
}
```

`messageFa` is part of the contract because the client must never have to map error codes to
Persian strings itself — new codes would render as blank or English text in released apps.

**Pagination** — cursor-based, not offset: `?limit=20&cursor=<opaque>`, responding
`{ "items": [...], "nextCursor": "..." | null }`. Offset pagination duplicates rows when the
underlying list changes, which it does constantly for video listings.

**Idempotency** — `Idempotency-Key` header honoured on `POST /licenses/issue` and
`POST /devices/register`.

---

## Endpoints

### Health

| Method | Path | Notes |
|---|---|---|
| `GET` | `/health` | liveness, no auth |
| `GET` | `/health/ready` | checks Postgres, Redis and MinIO reachability |

### Auth

| Method | Path | Notes |
|---|---|---|
| `POST` | `/auth/otp/request` | `{ phone }` → `{ requestId, expiresIn, resendAfter }`. Rate limited per phone and per IP. Always returns success shape whether or not the number exists, so the endpoint cannot enumerate users. |
| `POST` | `/auth/otp/verify` | `{ phone, code, device }` → tokens + user. Registers the device on first sight. |
| `POST` | `/auth/refresh` | `{ refreshToken }` → new pair. Reuse of a consumed token revokes the device session. |
| `POST` | `/auth/logout` | revokes the current device session |
| `GET` | `/auth/me` | current user + role + device |

### Devices

| Method | Path | Notes |
|---|---|---|
| `POST` | `/devices/register` | `{ fingerprint, platform, name, publicKey }` → device. Enforces the user's `max_devices`. |
| `GET` | `/devices` | the user's devices, with `lastSeenAt` and what each holds offline |
| `DELETE` | `/devices/:id` | release a device slot; revokes its keys and expires its downloads |

### Catalog

| Method | Path | Notes |
|---|---|---|
| `GET` | `/catalog/terms` | terms the user has enrollments in |
| `GET` | `/catalog/courses` | enrolled courses, with progress summary |
| `GET` | `/catalog/courses/:id` | course with sections and videos |
| `GET` | `/catalog/videos/:id` | video detail: renditions, chapters, attachments, progress |
| `GET` | `/catalog/search?q=` | Persian-normalized search across enrolled content |

Every catalog response is filtered by enrollment. There is no endpoint that returns a video the
caller cannot watch — the catalog is not a discovery surface, and a 404 for unenrolled content
is deliberate.

### Progress

| Method | Path | Notes |
|---|---|---|
| `GET` | `/progress/:videoId` | resume point |
| `PUT` | `/progress/:videoId` | `{ positionMs, completed }` |
| `POST` | `/progress/events` | batch of watch events; accepts queued offline events with their original timestamps |

The batch endpoint exists for offline sync: a device that watched three lectures on a plane
posts them all at once when it reconnects, and the server accepts the original client
timestamps (clamped to sane bounds) rather than stamping them all at arrival.

### Playback

| Method | Path | Notes |
|---|---|---|
| `POST` | `/playback/:videoId/session` | `{ deviceId, rendition? }` → playback session (manifest URL, wrapped key, watermark params, TTL). The core protected-playback call, detailed in [03-content-protection.md](03-content-protection.md). |
| `POST` | `/playback/sessions/:id/heartbeat` | keeps the session alive, returns current `revocationEpoch` so revocation lands within 30 s |
| `DELETE` | `/playback/sessions/:id` | ends the session; the server drops it and the client zeroes the key |

### Downloads and licensing

| Method | Path | Notes |
|---|---|---|
| `POST` | `/downloads` | `{ videoId, deviceId }` → a `.tihex` manifest + presigned segment URLs |
| `GET` | `/downloads` | what this user has offline, and where |
| `DELETE` | `/downloads/:id` | mark removed; frees the slot |
| `POST` | `/licenses/issue` | *(admin)* `{ userId, scope, notAfter, maxDevices }` → signed licence |
| `GET` | `/licenses/:id` | licence state and bound devices |
| `POST` | `/licenses/:id/revoke` | *(admin)* `{ reason }` — increments the user's revocation epoch |

### Admin *(role-guarded, M1)*

`/admin/terms`, `/admin/courses`, `/admin/enrollments`, `/admin/videos`,
`/admin/stats/videos/:id`, `/admin/stats/users/:id`, and
`/admin/investigate/watermark?text=` — which takes a watermark string read off a leaked
video and returns the account it identifies.

### Webhooks

| Method | Path | Notes |
|---|---|---|
| `POST` | `/webhooks/livekit` | LiveKit JWT-verified. `egress_ended` starts the pipeline. Idempotent on `egressId`. Always `200` for unknown events. Full payloads in [06-recording-pipeline.md](06-recording-pipeline.md). |

---

## Error codes

Stable strings, grouped by cause. The client switches on these.

| Code | Meaning |
|---|---|
| `VALIDATION_FAILED` | request body failed schema validation |
| `UNAUTHENTICATED` / `TOKEN_EXPIRED` | no or stale access token |
| `FORBIDDEN` | authenticated but not allowed |
| `OTP_INVALID` / `OTP_EXPIRED` / `OTP_RATE_LIMITED` | sign-in failures |
| `DEVICE_LIMIT_REACHED` | `max_devices` exceeded — the client offers to release one |
| `DEVICE_REVOKED` | this device was released elsewhere |
| `NOT_ENROLLED` | no active enrollment in the course |
| `LICENSE_MISSING` / `LICENSE_EXPIRED` / `LICENSE_REVOKED` | licence failures |
| `CONCURRENT_STREAM_LIMIT` | too many simultaneous streams |
| `DOWNLOAD_NOT_ALLOWED` | `courses.allow_download` is false |
| `VIDEO_NOT_READY` | still processing |
| `CAPTURE_ENVIRONMENT_BLOCKED` | recorder, VM or rooted device detected |
| `RATE_LIMITED` | generic throttle |
| `INTERNAL` | unexpected; `requestId` is the log key |

Each one maps to a specific Persian message and, where useful, a specific recovery action in
the app — `DEVICE_LIMIT_REACHED` opens the device manager rather than showing a dead end.
