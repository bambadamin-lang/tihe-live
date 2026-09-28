#!/usr/bin/env bash
# Exercise the recording pipeline without LiveKit running at all.
#
#   ./infra/scripts/fake-egress.sh path/to/lecture.mp4 <courseId>
#
# Uploads the file into tihe-raw with a metadata.json, then posts an egress_ended webhook to
# the API — exactly the shape LiveKit sends. This is how the video-management developer works
# on the pipeline while the live classroom is still being built
# (see docs/06-recording-pipeline.md).
set -euo pipefail

SRC=${1:?usage: fake-egress.sh <file.mp4> <courseId>}
COURSE_ID=${2:?usage: fake-egress.sh <file.mp4> <courseId>}
API=${API_URL:-http://localhost:3000/v1}
MC=${MC:-mc}

[[ -f "$SRC" ]] || { echo "no such file: $SRC" >&2; exit 1; }

# Crude ULID-ish ids — good enough for a fixture, and visibly fake in logs.
stamp() { date +%s%N | cut -c1-13; }
CLASS_ID="cls_dev$(stamp)"
SESSION_ID="ses_dev$(stamp)"
EGRESS_ID="EG_dev$(stamp)"
PREFIX="recordings/${CLASS_ID}/${SESSION_ID}"

DURATION_NS=0
if command -v ffprobe >/dev/null; then
  SECS=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SRC" | cut -d. -f1)
  DURATION_NS=$(( ${SECS:-0} * 1000000000 ))
fi
SIZE=$(wc -c < "$SRC" | tr -d ' ')

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/metadata.json" <<META
{
  "classId": "${CLASS_ID}",
  "sessionId": "${SESSION_ID}",
  "courseId": "${COURSE_ID}",
  "title": "جلسه آزمایشی $(date -u +%H:%M)",
  "teacherId": null,
  "scheduledStartAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "actualStartAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "actualEndAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "participantCount": 1,
  "livekitRoom": "class-${CLASS_ID}",
  "egressIds": ["${EGRESS_ID}"]
}
META

echo "uploading to tihe-raw/${PREFIX}/ ..."
$MC cp "$SRC" "local/tihe-raw/${PREFIX}/composite.mp4"
$MC cp "$TMP/metadata.json" "local/tihe-raw/${PREFIX}/metadata.json"

echo "posting egress_ended to ${API}/webhooks/livekit ..."
curl -sS -X POST "${API}/webhooks/livekit" \
  -H 'Content-Type: application/json' \
  -H "Authorization: ${LIVEKIT_DEV_TOKEN:-dev}" \
  -d @- <<PAYLOAD
{
  "event": "egress_ended",
  "egressInfo": {
    "egressId": "${EGRESS_ID}",
    "roomName": "class-${CLASS_ID}",
    "status": "EGRESS_COMPLETE",
    "startedAt": $(date +%s)000000000,
    "endedAt": $(date +%s)000000000,
    "fileResults": [{
      "filename": "${PREFIX}/composite.mp4",
      "location": "s3://tihe-raw/${PREFIX}/composite.mp4",
      "size": ${SIZE},
      "duration": ${DURATION_NS}
    }]
  }
}
PAYLOAD

echo
echo "done. watch the ingest worker, or poll:  GET ${API}/admin/videos"
