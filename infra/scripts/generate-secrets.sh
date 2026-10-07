#!/usr/bin/env bash
# Generate the cryptographic material the API needs for local development.
#
#   ./infra/scripts/generate-secrets.sh
#
# Prints environment variables to paste into .env at the repo root (services/live reads
# JWT_SECRET, INTERNAL_API_TOKEN and LIVE_TICKET_SECRET from its own .env).
#
# Produces:
#   KEK              — wraps every content key. Losing it makes every video undecryptable.
#   LICENSE_*_KEY    — Ed25519 keypair. The private half signs licences; the public half is
#                      embedded in the client and verifies them offline.
#   JWT_SECRET       — signs access tokens; services/live verifies them with the same value.
#   PASSWORD_PEPPER  — mixed into every password hash.
#   INTERNAL_API_TOKEN — services/live's key to the API's internal directory.
#   LIVE_TICKET_SECRET — services/live's own gateway tickets.
#
# DEVELOPMENT ONLY. In production these come from the deployment environment or a secret
# manager, and the private keys never touch a developer machine. See docs/10-open-questions.md Q8.
set -euo pipefail

command -v openssl >/dev/null || { echo "openssl is required" >&2; exit 1; }

b64() { openssl rand -base64 "$1" | tr -d '\n'; }

KEK=$(b64 32)
JWT_SECRET=$(b64 48)
PASSWORD_PEPPER=$(b64 32)
INTERNAL_API_TOKEN=$(b64 48)
LIVE_TICKET_SECRET=$(b64 48)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

openssl genpkey -algorithm ed25519 -out "$TMP/license_private.pem" 2>/dev/null
openssl pkey -in "$TMP/license_private.pem" -pubout -out "$TMP/license_public.pem" 2>/dev/null

# Strip PEM armour so the keys fit on one .env line.
PRIV=$(grep -v -- '-----' "$TMP/license_private.pem" | tr -d '\n')
PUB=$(grep -v -- '-----' "$TMP/license_public.pem" | tr -d '\n')

cat <<VARS

# ─── generated $(date -u +%Y-%m-%dT%H:%M:%SZ) — paste into .env at the repo root ───

# Wraps every content encryption key. Back this up separately from the database:
# database + KEK together decrypt everything, either one alone decrypts nothing.
KEK_BASE64=$KEK

# Ed25519 licence signing keypair.
LICENSE_PRIVATE_KEY_BASE64=$PRIV
LICENSE_PUBLIC_KEY_BASE64=$PUB

# Access token signing. services/live needs the same value.
JWT_SECRET=$JWT_SECRET

# Mixed into password hashes so a database dump alone cannot be brute-forced.
PASSWORD_PEPPER=$PASSWORD_PEPPER

# services/live calls the API's internal directory with this (as API_INTERNAL_TOKEN).
INTERNAL_API_TOKEN=$INTERNAL_API_TOKEN

# services/live only: signs its two-minute classroom gateway tickets.
LIVE_TICKET_SECRET=$LIVE_TICKET_SECRET

VARS

echo "Embed this public key in the Flutter client (apps/player/lib/core/security/license_key.dart):"
echo
echo "  $PUB"
echo
echo "The private key above must never reach the client, a log, or version control."
