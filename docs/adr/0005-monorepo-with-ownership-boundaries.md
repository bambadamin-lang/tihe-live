# ADR-0005 — Monorepo with folder ownership

**Status:** Accepted · 2026-09-27

## Context

Two developers: one on the live classroom, one on video management. They share an API contract,
an auth model and a data model, and the live→VOD handoff is the single most important interface
in the system.

## Decision

One repository. `apps/`, `services/`, `packages/`, `infra/`. Each developer owns specific
folders outright. `packages/contracts` is shared and requires a PR.

## Consequences

**Good.** The shared contract cannot drift, because there is one copy of it. A change spanning
the live and VOD sides is one atomic commit. One CI pipeline, one dependency set, one place to
look.

**Bad.** Both developers see each other's churn in `git log`. CI runs more than strictly
needed on any given change (mitigated by Turborepo filters). A repo-wide mistake affects both.

**Guardrail.** Ownership is documented in [09-team-workflow.md](../09-team-workflow.md) and
enforced socially, not by tooling — with two people, `CODEOWNERS` would be ceremony. If it
starts hurting, ADR-000X will split `services/live` out.
