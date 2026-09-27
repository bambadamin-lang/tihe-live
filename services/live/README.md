# services/live — the live classroom

Classes and sessions, LiveKit orchestration, the classroom gateway (WebSocket), and
server-side recording. Design: [docs/11-live-classroom.md](../../docs/11-live-classroom.md).
Decisions: ADR-0010 (gateway), ADR-0011 (capture), ADR-0012 (own database, client-facing).

```
src/core/          the classroom rules, framework-free: capabilities, room state, reducer
src/classroom/     room actor (one per class), hub, WebSocket gateway, Redis room store
src/sessions/      start / join / end, and the join response (tokens, watermark, capture policy)
src/recording/     egress + metadata.json, in the order docs/06 needs
src/classes/       class CRUD and who may host or attend
src/livekit/       the only code that talks to LiveKit (port + adapter)
src/directory/     courses, enrollment and profiles from services/api (stub or HTTP)
src/persistence/   tihe_live database (Prisma) and an in-memory twin
egress-template/   the page LiveKit Egress renders into composite.mp4
```

## Run it

```bash
cp services/live/.env.example services/live/.env        # fill JWT_SECRET, LIVE_TICKET_SECRET
docker compose -f infra/docker/compose.dev.yml --profile live up -d
pnpm --filter @tihe/live prisma migrate deploy
pnpm --filter @tihe/live start:dev                        # :3100, REST /v1/live, WS /v1/live/ws

# a teacher token for the stub directory (dev/directory.json), then start a class
TOKEN=$(pnpm -s --filter @tihe/live dev-token usr_01J8ZB00000000000000000001 teacher)
curl -X POST localhost:3100/v1/live/classes -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"courseId":"crs_01J8ZA00000000000000000001","title":"جلسه آزمایشی"}'
```

Without `LIVE_DATABASE_URL`, `REDIS_URL` or `S3_ENDPOINT` it runs fully in memory, which is
enough to drive the Flutter example app against it.

## Test it

```bash
pnpm --filter @tihe/live test      # rules, then a whole class over REST + WebSocket
# plus the Postgres and Redis integration tests:
LIVE_TEST_DATABASE_URL=postgresql://tihe:tihe_dev_password@localhost:5432/tihe_live \
LIVE_TEST_REDIS_URL=redis://localhost:6379 pnpm --filter @tihe/live test
```
