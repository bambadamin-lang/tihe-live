# Infrastructure

Everything needed to run TIHE Live locally, and the shape of the production deployment.

## Development stack

```bash
# Postgres + Redis + MinIO (what the video-management side needs)
docker compose -f infra/docker/compose.dev.yml up -d

# ...plus LiveKit + Egress (what the live-classroom side needs)
docker compose -f infra/docker/compose.dev.yml --profile live up -d
```

| Service | Where | Credentials (dev only) |
|---|---|---|
| PostgreSQL | `localhost:5432` | `tihe` / `tihe_dev_password`, db `tihe` |
| Redis | `localhost:6379` | none |
| MinIO S3 API | `localhost:9000` | `tihe_minio` / `tihe_minio_dev_password` |
| MinIO console | http://localhost:9001 | same |
| LiveKit | `ws://localhost:7880` | `devkey` / `devsecret_...` |
| services/live (run on host) | `http://localhost:3100/v1/live`, WS `/v1/live/ws` | — |

`minio-init` runs once on startup and creates `tihe-raw` and `tihe-vod`, sets both to
private, and enables versioning on `tihe-vod`. If you ever see those buckets public,
something has gone wrong — every recording would be readable by anyone who guessed a key.

`postgres-init/02-live-database.sql` creates a second database, `tihe_live`, for
`services/live` (ADR-0012). Init scripts only run on a fresh volume — on an existing one, create
it by hand or `docker compose down -v` first.

Postgres is initialised with the `fa-IR` ICU collation and the `pg_trgm`, `unaccent` and
`pgcrypto` extensions (`docker/postgres-init/`), because Persian search depends on them.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/generate-secrets.sh` | Generates the KEK, the Ed25519 licence keypair, the JWT secret and the OTP pepper, and prints them as `.env` lines. Development only. |
| `scripts/minio-init.sh` | Bucket creation and lockdown. Runs automatically in Compose. |
| `scripts/fake-egress.sh` | Drops an MP4 into `tihe-raw` and posts a LiveKit `egress_ended` webhook — exercises the whole recording pipeline with no LiveKit running. |

`fake-egress.sh` is the one worth knowing about: it is what lets the video-management
developer build the entire pipeline before the live classroom exists.

## Secrets

Four pieces of cryptographic material, described fully in
[../docs/03-content-protection.md](../docs/03-content-protection.md):

| Name | Role | If it leaks |
|---|---|---|
| `KEK_BASE64` | Wraps every content key | Every video is decryptable, given the database too |
| `LICENSE_PRIVATE_KEY_BASE64` | Signs licences | Anyone can mint licences; rotation invalidates all outstanding ones |
| `LICENSE_PUBLIC_KEY_BASE64` | Verifies licences, embedded in the client | Harmless — it is meant to be public |
| `JWT_SECRET` | Signs access/refresh tokens | Session forgery |
| `OTP_PEPPER` | Hardens OTP hashes | Database dumps become brute-forceable for live codes |

**Backup rule:** the KEK must be backed up **separately from the database**. Together they
decrypt everything; either alone decrypts nothing. Storing the KEK in the same backup archive
as the database defeats the point of wrapping keys at all.

Where these live in production is [open question Q8](../docs/10-open-questions.md).

## Production deployment (sketch, not yet built)

Single server, Docker Compose, nginx terminating TLS:

```
            ┌──────────── nginx (TLS, rate limit) ────────────┐
            │  api.tihe.ir → services/api                     │
            │  api.tihe.ir/v1/live → services/live (+ws)      │
            │  live.tihe.ir → livekit (ws upgrade)            │
            │  cdn.tihe.ir → minio (tihe-vod, presigned only) │
            └─────────────────────────────────────────────────┘
```

Notes for when this gets built (M2–M3):

- Media bytes never pass through the API. Clients fetch segments straight from MinIO by
  presigned URL, so nginx proxies MinIO directly and the API stays small.
- LiveKit needs its UDP port range reachable, which usually means host networking rather
  than bridged Docker networking.
- Egress renders each room composite in headless Chrome — budget roughly one CPU core per
  concurrently recorded class, and keep `shm_size` at 1 GB or recordings crash partway.
- `media-worker` is the other CPU consumer (ffmpeg). Run it on separate hardware from
  LiveKit if classes are recorded while older ones are still transcoding.
- Backups: nightly `pg_dump`, MinIO replication or `mc mirror` to a second location, and the
  KEK held somewhere neither of those backups reaches.
