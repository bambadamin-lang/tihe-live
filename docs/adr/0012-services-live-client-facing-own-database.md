# ADR-0012 — `services/live` is client-facing and has its own database

**Status:** Accepted · 2026-09-27 · Amends [02-architecture.md](../02-architecture.md) ("services/api
is the only service the client talks to").

## Context

The live classroom needs REST (classes, sessions, join), a WebSocket (the control plane from
ADR-0010) and LiveKit webhooks. It also needs its own tables: classes, sessions, attendance,
saved layouts, audit events. The API is owned and changed by a different session.

## Decision

- **Client-facing**: clients call `services/live` directly. In production nginx routes
  `/v1/live/*` (including the WebSocket upgrade) to it, so clients still see one origin and
  one certificate pin. In development it listens on `:3100`.
- **Own database**: `tihe_live` on the same PostgreSQL server, with its own Prisma schema,
  migrations and generated client output.
  - A second *schema* in the same database was rejected. Prisma's migration table and
    `migrate reset` would let one service damage the other's tables, and both generate
    commands would fight over one `@prisma/client` directory.
- **Identity**: `services/live` verifies the access tokens issued by `services/api`, behind an
  `AccessTokenVerifier` interface that checks `iss` and `aud`. The claims shape is part of
  `packages/contracts`.
- **Course data**: enrollment, course policy and the phone number for the watermark come
  through a `CourseDirectory` interface. It has an HTTP implementation against the API's
  internal endpoints and a development stub, so the classroom is never blocked on the API.

## Consequences

**Good.** Neither service can break the other's migrations. The classroom can be developed and
tested before the API exists.

**Bad.**
- For now both services share the HS256 JWT secret, so `services/live` could in principle
  mint user tokens. Moving the API to EdDSA with a published JWKS removes that; it is proposed
  to the API owner.
- There are two databases to back up, though both run in the same Postgres instance.
- Cross-database joins are impossible. `services/live` stores ids from the API
  (`usr_`, `crs_`) without foreign keys and resolves names through `CourseDirectory`.
