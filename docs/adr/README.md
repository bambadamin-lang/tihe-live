# Architecture Decision Records

One short file per significant decision. Format: context → decision → consequences.

A decision that turns out wrong is not edited in place — a new ADR supersedes it, and the old
one gets a `Superseded by ADR-000X` line. The history is the point.

| # | Decision | Status |
|---|---|---|
| [0001](0001-flutter-for-all-clients.md) | Flutter for all client platforms | Accepted (platform scope superseded by 0009) |
| [0002](0002-nestjs-postgres-backend.md) | NestJS + PostgreSQL backend | Accepted |
| [0003](0003-custom-aes-licensing-over-commercial-drm.md) | Custom AES + licence server instead of commercial DRM | Accepted |
| [0004](0004-self-hosted-minio-storage.md) | Self-hosted infrastructure with MinIO | Accepted |
| [0005](0005-monorepo-with-ownership-boundaries.md) | Monorepo with folder ownership | Accepted |
| [0006](0006-livekit-for-live-classes.md) | LiveKit for the live classroom | Accepted (data-channel part superseded by 0010) |
| [0007](0007-phone-otp-authentication.md) | Phone + SMS OTP authentication | Accepted |
| [0008](0008-loopback-hls-server-for-playback.md) | Loopback HLS server for decryption | Accepted |
| [0009](0009-four-platforms-classroom-desktop-first.md) | Four platforms; classroom desktop-first | Accepted |
| [0010](0010-classroom-control-plane-websocket-gateway.md) | Classroom control plane: WebSocket gateway | Accepted |
| [0011](0011-live-capture-guard-censor-and-attribute.md) | Live class capture: block, detect, censor, alert, attribute | Accepted |
| [0012](0012-services-live-client-facing-own-database.md) | `services/live` client-facing, own database | Accepted |
