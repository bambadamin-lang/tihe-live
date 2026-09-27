#!/bin/sh
# Create and lock down the buckets the pipeline expects.
# Run automatically by the minio-init service in compose.dev.yml.
set -eu

echo "waiting for minio at ${MINIO_ENDPOINT}..."
until mc alias set local "${MINIO_ENDPOINT}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" 2>/dev/null; do
  sleep 1
done

# tihe-raw: raw recordings from LiveKit Egress. Short retention — an unencrypted master copy
# must not sit here indefinitely (see docs/06-recording-pipeline.md).
mc mb --ignore-existing local/tihe-raw

# tihe-vod: packaged, already-encrypted HLS segments served to clients by presigned URL.
mc mb --ignore-existing local/tihe-vod

# Both buckets are private. This is not a default we rely on — we set it explicitly, because
# a public bucket would hand out every recording to anyone who guessed a key.
mc anonymous set none local/tihe-raw
mc anonymous set none local/tihe-vod

# Versioning on the VOD bucket: a bad packaging run should not destroy the previous good
# output irrecoverably.
mc version enable local/tihe-vod

echo
echo "buckets ready:"
mc ls local
echo
echo "NOTE: anonymous access is disabled on both buckets. Clients receive presigned URLs"
echo "      with a 2-minute TTL, minted by the API after licence checks pass."
