#!/bin/sh
# Create and lock down the buckets the pipeline expects. Plain S3 requests signed by curl
# (--aws-sigv4), so this works against any S3-compatible store, not one vendor's admin tool.
# Run automatically by the storage-init service in Compose.
set -eu
: "${S3_ENDPOINT:?}" "${S3_ACCESS_KEY:?}" "${S3_SECRET_KEY:?}"
region="${S3_REGION:-us-east-1}"

# s3 METHOD PATH [curl args...] prints the HTTP status.
s3() {
  method=$1
  path=$2
  shift 2
  curl -s -o /dev/null -w '%{http_code}' --aws-sigv4 "aws:amz:${region}:s3" \
    --user "${S3_ACCESS_KEY}:${S3_SECRET_KEY}" -X "$method" "$@" "${S3_ENDPOINT}${path}"
}

expect() {
  what=$1
  status=$2
  shift 2
  for ok in "$@"; do
    [ "$status" = "$ok" ] && return 0
  done
  echo "storage-init: $what failed with HTTP $status" >&2
  exit 1
}

echo "waiting for storage at ${S3_ENDPOINT}..."
until [ "$(s3 GET /)" = 200 ]; do sleep 1; done

for bucket in tihe-raw tihe-vod; do
  # tihe-raw holds raw Egress recordings (short retention, docs/06); tihe-vod holds packaged,
  # already-encrypted HLS served by presigned URL.
  expect "create $bucket" "$(s3 PUT "/$bucket")" 200 409
  # Private is the S3 default, but it is set explicitly: a public bucket would hand out every
  # recording to anyone who guessed a key.
  expect "lock $bucket" "$(s3 DELETE "/$bucket?policy")" 200 204 404
done

# Versioning on the VOD bucket: a bad packaging run should not destroy the previous good output
# irrecoverably.
expect "version tihe-vod" "$(s3 PUT '/tihe-vod?versioning' -H 'content-type: application/xml' \
  --data '<VersioningConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Status>Enabled</Status></VersioningConfiguration>')" 200

anonymous=$(curl -s -o /dev/null -w '%{http_code}' "${S3_ENDPOINT}/tihe-vod")
expect "anonymous access check (must be refused)" "$anonymous" 403

echo "buckets ready: tihe-raw, tihe-vod (private; clients get 2-minute presigned URLs)"
