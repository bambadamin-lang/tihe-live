# ADR-0002 — NestJS + PostgreSQL backend

**Status:** Accepted · 2026-09-27

## Context

The backend needs a REST API, a job queue for the media pipeline, and a relational model with
real constraints (enrollments, licences, device limits). Two developers share an API contract.

## Decision

NestJS (TypeScript) with PostgreSQL via Prisma, Redis + BullMQ for jobs.

## Consequences

**Good.** `packages/contracts` types are shared between the API and tooling with no
duplication or codegen step. NestJS's module/guard/interceptor structure suits
permission-heavy code, which this is. BullMQ is a mature queue for the ffmpeg pipeline.
Postgres gives us the constraints that keep licence and enrollment logic honest.

**Bad.** Node is not the fastest choice for streaming media bytes — mitigated by never
proxying media through the API: clients fetch segments from MinIO directly via presigned URLs.
ffmpeg work happens in a separate worker process so it cannot block the API event loop.

**Rejected because.** Go would be faster but slower to build in, with no type sharing with the
client tooling. Django's free admin panel was tempting, but we would have lost the shared
contract package, which is the main defence against the two developers diverging.
