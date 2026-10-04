# Infrastructure

Everything needed to run TIHE Live locally, and the shape of the production deployment.

## Development stack

```bash
# Postgres + Redis + S3 storage (what the video-management side needs)
docker compose -f infra/docker/compose.dev.yml up -d

# ...plus LiveKit + Egress (what the live-classroom side needs)
docker compose -f infra/docker/compose.dev.yml --profile live up -d
```

| Service | Where | Credentials (dev only) |
|---|---|---|
| PostgreSQL | `localhost:5432` | `tihe` / `tihe_dev_password`, db `tihe` |
| Redis | `localhost:6379` | none |
| S3 storage (RustFS) | `localhost:9000` | `tihe_minio` / `tihe_minio_dev_password` |
| Storage console | http://localhost:9001 | same |
| LiveKit | `ws://localhost:7880` | `devkey` / `devsecret_...` |
| services/live (run on host) | `http://localhost:3100/v1/live`, WS `/v1/live/ws` | — |

`storage-init` runs once on startup and creates `tihe-raw` and `tihe-vod`, sets both to
private, and enables versioning on `tihe-vod`. Storage is RustFS because MinIO no longer
publishes images; the code only uses an S3 client, so any S3-compatible store works (ADR-0004). If you ever see those buckets public,
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
| `scripts/storage-init.sh` | Bucket creation and lockdown over plain S3. Runs automatically in Compose. |
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

## Run the server on a PC

Until there is a VPS, the whole server (API, live classroom, recording, video processing,
storage, databases) runs on one PC with Docker. On a new PC, from the repository folder:

```powershell
# Windows, Docker Desktop (as administrator, so it can open the firewall ports)
powershell -ExecutionPolicy Bypass -File infra\scripts\server-setup.ps1 -AdminPhone 09121234567 -AdminName "مدیر"
```

```bash
# Linux, macOS or WSL
./infra/scripts/server-setup.sh --admin-phone 09121234567 --admin-name "مدیر"
```

It finds the PC's network address (or pass `-HostAddress` / `--host`), writes the secrets once
into `infra/docker/server/.env`, builds and starts everything
([`docker/compose.server.yml`](docker/compose.server.yml)), and creates the first admin with a
temporary password it prints. Then it prints the one address to give the app and its
installer, `http://<this PC>:8080`.

- **Back up `infra/docker/server/.env`** privately. The database and `KEK_BASE64` together
  decrypt every video; without the file nobody can sign in again.
- Running the setup again is safe: it keeps the secrets and the data, applies new migrations
  and rebuilds what changed. Use it after `git pull` to update the server.
- Ports: 8080 (the app), 9000 (video downloads), 7880–7881/TCP and 50000–50100/UDP (live
  media). Devices on the same network work out of the box; reaching the PC from the internet
  needs those ports forwarded on the router and the router's public address as `--host`.
- Moving to a VPS later: copy `.env` and the Docker volumes, run the setup there with the new
  address, and update the server address students use (the installer's default, or the
  sign-in screen's "change server").
