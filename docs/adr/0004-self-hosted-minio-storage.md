# ADR-0004 — Self-hosted infrastructure with MinIO

**Status:** Accepted · 2026-09-27

## Context

The platform serves an Iranian institute. AWS and GCP accounts and payments are commonly
unavailable. Video storage grows quickly and bandwidth is the dominant running cost.

## Decision

Self-hosted server (own hardware or VPS) with MinIO for S3-compatible object storage, deployed
with Docker Compose.

## Consequences

**Good.** No sanctions exposure, no billing dependency, lowest cost at scale, full control over
data residency — which matters when the data is students' watch behaviour. Local latency for
local students.

**Bad.** We own uptime, backups and disaster recovery. No managed CDN, so bandwidth scaling is
manual. Q9 in [10-open-questions.md](../10-open-questions.md) tracks the unanswered backup
question.

**Hedge.** All object access goes through an S3 client configured entirely by environment
variables. Moving to ArvanCloud, Liara or any S3-compatible provider is a configuration
change, not a code change. Nothing in the codebase names MinIO outside `infra/`.
