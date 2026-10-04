# The TIHE server's Node services, one image per target:
#
#   docker build -f infra/docker/Dockerfile --target api .
#
# Built by infra/docker/compose.server.yml. Each target is the whole built workspace, which
# costs some disk but keeps the workspace links (`@tihe/*`) and Prisma clients exactly as in
# development.

# The full image, not -slim: it already has the OpenSSL Prisma's engines need, so building
# needs no package mirror (often unreachable from Iran).
FROM node:22-bookworm AS build
WORKDIR /app
RUN corepack enable
COPY . .
RUN pnpm install --frozen-lockfile
RUN pnpm build

FROM node:22-bookworm AS base
WORKDIR /app
RUN corepack enable
ENV NODE_ENV=production
COPY --from=build /app /app

FROM base AS api
WORKDIR /app/services/api
EXPOSE 3000
CMD ["node", "dist/main.js"]

FROM base AS live
WORKDIR /app/services/live
EXPOSE 3100
CMD ["node", "--enable-source-maps", "dist/main.js"]

FROM base AS media-worker
# Transcoding and packaging.
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app/services/media-worker
CMD ["node", "dist/worker.js"]

# Applies both databases' migrations, then exits. Run before the services start.
FROM base AS migrate
WORKDIR /app
CMD ["sh", "-c", "cd packages/db && npx prisma migrate deploy && cd ../../services/live && npx prisma migrate deploy"]
