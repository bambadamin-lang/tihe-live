# Team Workflow

Two developers, one repo. These rules exist to keep you out of each other's way.

## Branches

```
main                        protected, always deployable
feat/<area>-<short-desc>    e.g. feat/vod-offline-download
fix/<area>-<short-desc>
claude/<topic>              branches created by Claude Code sessions
```

`<area>` is one of `vod`, `live`, `player`, `api`, `media`, `core`, `infra`, `docs`.
The area prefix makes it obvious at a glance whose work a branch is.

## Ownership

| Path | Owner | Rule |
|---|---|---|
| `services/api`, `services/media-worker`, `services/ingest-worker` | you | push freely on your own branches |
| `apps/player`, `packages/secure-core` | you | as above |
| `services/live` | friend | as above |
| `packages/contracts` | **shared** | **PR + the other person's review, always** |
| `infra/`, `docs/`, root config | **shared** | PR, review appreciated but not blocking |

The reason `contracts` is special: it is the only place where one of you can break the
other's build. Treat a change there as a small API design conversation.

## Commits

Conventional Commits, with the area as the scope:

```
feat(api): add device registration endpoint
fix(player): stop watermark drifting off-screen on narrow windows
chore(infra): pin minio image
docs(protection): document clock-rollback defence
```

## Definition of done

A change is done when:

1. It builds, lints and type-checks (`pnpm check` at the root).
2. It has a test if it contains logic that could silently be wrong — crypto, licence
   validity, permission checks and anything with money or time in it, always.
3. `docs/` is updated if a decision changed.
4. An ADR exists if an architectural decision changed.

## When you disagree with a decision in `docs/`

Change the doc and add an ADR that supersedes the old one. Do not leave the docs saying one
thing and the code doing another — a stale doc is worse than no doc, because the next person
(or the next Claude session) will believe it.

## Working with Claude Code on this repo

`CLAUDE.md` at the root carries the conventions. When you start a session on a specific area,
point it at the relevant doc first — `docs/03-content-protection.md` for anything touching
keys, `docs/06-recording-pipeline.md` for anything crossing the live/VOD boundary.
