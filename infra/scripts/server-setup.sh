#!/usr/bin/env bash
# Sets up and starts the whole TIHE server on this machine, with one command:
#
#   ./infra/scripts/server-setup.sh --admin-phone 09121234567 --admin-name "مدیر"
#
# Options: --host <address students use to reach this PC> (detected if left out).
# Needs only Docker. Safe to run again: it keeps the secrets, applies new migrations, rebuilds
# changed services, and only creates the admin when asked to.
set -euo pipefail

cd "$(dirname "$0")/../.."
COMPOSE=(docker compose -f infra/docker/compose.server.yml --env-file infra/docker/server/.env)

HOST="" ADMIN_PHONE="" ADMIN_NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --admin-phone) ADMIN_PHONE="$2"; shift 2 ;;
    --admin-name) ADMIN_NAME="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

docker compose version >/dev/null 2>&1 || {
  echo "Docker with Compose is required: https://docs.docker.com/get-docker/" >&2
  exit 1
}

if [ -z "$HOST" ]; then
  # The address this PC uses on its network: what students' devices on the same network reach.
  HOST=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}' | head -1)
  HOST=${HOST:-$(hostname -I 2>/dev/null | awk '{print $1}')}
  [ -n "$HOST" ] || { echo "Could not find this PC's address; pass --host" >&2; exit 1; }
fi

echo "› Configuring for $HOST"
if command -v node >/dev/null 2>&1; then
  node infra/scripts/server-config.mjs --host "$HOST"
else
  docker run --rm -v "$PWD:/w" -w /w node:22-alpine node infra/scripts/server-config.mjs --host "$HOST"
fi

echo "› Building and starting (the first build takes several minutes)"
"${COMPOSE[@]}" up -d --build

echo "› Waiting for the server"
for _ in $(seq 1 90); do
  if curl -fs "http://localhost:8080/v1/health" >/dev/null 2>&1; then break; fi
  sleep 2
done
curl -fs "http://localhost:8080/v1/health" >/dev/null || {
  echo "The server did not come up. See: ${COMPOSE[*]} logs api live" >&2
  exit 1
}

if [ -n "$ADMIN_PHONE" ]; then
  echo "› Creating the admin"
  "${COMPOSE[@]}" exec -T api node dist/cli/create-admin.js \
    --phone "$ADMIN_PHONE" --name "${ADMIN_NAME:-مدیر}"
fi

cat <<DONE

TIHE is running.
  Server address for the app and its installer:  http://$HOST:8080
  Allow through the firewall: 8080, 9000, 7880-7881 (TCP) and 50000-50100 (UDP).
  Back up infra/docker/server/.env somewhere private: without it the videos and accounts are lost.
DONE
