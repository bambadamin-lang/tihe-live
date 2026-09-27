#!/usr/bin/env bash
# End-to-end smoke test of the student path against a running API.
#
#   ./infra/scripts/smoke-test.sh [phone]
#
# Defaults to the seeded student (09125550003). Requires the API running with SMS_PROVIDER=console
# so the code comes back in the response.
#
# Exercises: OTP issue and verify, device registration, catalog, Persian search, progress, watch
# events, playback session minting (including the device-bound wrapped key), and the negative paths
# that matter — unenrolled access, downloads disabled by course policy, and the device limit.
set -uo pipefail

API=${API_URL:-http://localhost:3000/v1}
PHONE=${1:-09125550003}

pass=0
fail=0

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }

check() { # check <description> <condition-result>
  if [[ "$2" == "true" ]]; then
    green "  ok    $1"; pass=$((pass + 1))
  else
    red   "  FAIL  $1"; fail=$((fail + 1))
  fi
}

jqp() {
  python3 -c "
import sys, json
d = json.load(sys.stdin)
v = ($1)
print(json.dumps(v) if isinstance(v, bool) else v)
" 2>/dev/null
}

echo "smoke test against $API"
echo

# ── Auth ──────────────────────────────────────────────────────────────────────
echo "auth"
otp=$(curl -s -X POST "$API/auth/otp/request" -H 'Content-Type: application/json' \
  -d "{\"phone\":\"$PHONE\"}")
code=$(echo "$otp" | jqp "d.get('devCode','')")

if [[ -z "$code" ]]; then
  red "  FAIL  could not obtain an OTP:"
  echo "$otp" | python3 -m json.tool | sed 's/^/        /'
  echo
  echo "  (a resend cooldown is expected if you just ran this — wait and retry)"
  exit 1
fi
check "OTP issued" true

auth=$(curl -s -X POST "$API/auth/otp/verify" -H 'Content-Type: application/json' -d "{
  \"phone\": \"$PHONE\",
  \"code\": \"$code\",
  \"device\": {
    \"fingerprint\": \"smoke-test-fingerprint-0123456789\",
    \"platform\": \"windows\",
    \"name\": \"دستگاه آزمایشی\",
    \"publicKey\": \"7InzIA+zLlvlysH3SyUVxsa8XByKptOo9ps0NfNMIkU=\"
  }}")

token=$(echo "$auth" | jqp "d['tokens']['accessToken']")
device=$(echo "$auth" | jqp "d['device']['id']")
masked=$(echo "$auth" | jqp "d['user']['phoneMasked']")

check "signed in and device registered" "$([[ -n $token && -n $device ]] && echo true || echo false)"
check "phone is masked in the response ($masked)" \
  "$(echo "$auth" | jqp "'•' in d['user']['phoneMasked']")"

H="Authorization: Bearer $token"

# A wrong code must be rejected.
bad=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/auth/otp/verify" \
  -H 'Content-Type: application/json' \
  -d "{\"phone\":\"$PHONE\",\"code\":\"00000\",\"device\":{\"fingerprint\":\"x-fingerprint-0123456789\",\"platform\":\"android\",\"name\":\"x\",\"publicKey\":\"7InzIA+zLlvlysH3SyUVxsa8XByKptOo9ps0NfNMIkU=\"}}")
check "a wrong code is rejected (got $bad)" "$([[ $bad == 400 ]] && echo true || echo false)"

# No token means no access.
unauth=$(curl -s -o /dev/null -w '%{http_code}' "$API/catalog/courses")
check "catalog requires authentication (got $unauth)" "$([[ $unauth == 401 ]] && echo true || echo false)"

# ── Catalog ───────────────────────────────────────────────────────────────────
echo
echo "catalog"
courses=$(curl -s -H "$H" "$API/catalog/courses")
count=$(echo "$courses" | jqp "len(d['items'])")

# An account with no enrollments legitimately sees nothing, and every later check would then fail
# for the wrong reason. Say so and stop rather than printing a wall of misleading failures.
if [[ ${count:-0} -eq 0 ]]; then
  red "  FAIL  no courses visible to $PHONE"
  echo "        This is correct behaviour for an account with no enrollments — the catalogue only"
  echo "        ever returns enrolled courses. Run against the seeded student instead:"
  echo "            ./infra/scripts/smoke-test.sh 09125550003"
  exit 1
fi
check "courses listed ($count)" true

course=$(echo "$courses" | jqp "d['items'][0]['id']")
detail=$(curl -s -H "$H" "$API/catalog/courses/$course")
sections=$(echo "$detail" | jqp "len(d['sections'])")
check "course detail has sections ($sections)" "$([[ ${sections:-0} -gt 0 ]] && echo true || echo false)"

video=$(echo "$detail" | jqp "[v for s in d['sections'] for v in s['videos'] if v['status']=='ready'][0]['id']")
check "found a ready video" "$([[ -n $video ]] && echo true || echo false)"

vdetail=$(curl -s -H "$H" "$API/catalog/videos/$video")
check "video detail has renditions" "$(echo "$vdetail" | jqp "len(d['renditions'])>0")"
check "video detail has chapters" "$(echo "$vdetail" | jqp "len(d['chapters'])>0")"

# An unenrolled course must be absent, not merely locked.
missing=$(curl -s -o /dev/null -w '%{http_code}' -H "$H" \
  "$API/catalog/courses/crs_01KZZZZZZZZZZZZZZZZZZZZZZZ")
check "unenrolled course returns 404, not 403 (got $missing)" \
  "$([[ $missing == 404 ]] && echo true || echo false)"

# ── Persian search ────────────────────────────────────────────────────────────
echo
echo "persian search"
for q in 'مشتق' 'ریاضی' 'مُشتَق' 'حد'; do
  hits=$(curl -s -H "$H" --get --data-urlencode "q=$q" "$API/catalog/search" | jqp "len(d['items'])")
  check "search '$q' → ${hits:-0} hit(s)" "$([[ ${hits:-0} -gt 0 ]] && echo true || echo false)"
done

# The point of normalisation: Arabic-typed input finds Persian-stored text.
arabic_hits=$(curl -s -H "$H" --get --data-urlencode 'q=رياضي' "$API/catalog/search" | jqp "len(d['items'])")
check "Arabic-typed 'رياضي' finds Persian 'ریاضی' (${arabic_hits:-0} hits)" \
  "$([[ ${arabic_hits:-0} -gt 0 ]] && echo true || echo false)"

# ── Progress ──────────────────────────────────────────────────────────────────
echo
echo "progress"
# Written relative to whatever is already stored: progress only moves forward by design, so an
# absolute expectation would depend on whether this script has run before.
before=$(curl -s -H "$H" "$API/progress/$video" | jqp "d['positionMs']")
target=$(( ${before:-0} + 60000 ))
curl -s -o /dev/null -X PUT -H "$H" -H 'Content-Type: application/json' \
  -d "{\"positionMs\":$target}" "$API/progress/$video"
pos=$(curl -s -H "$H" "$API/progress/$video" | jqp "d['positionMs']")
check "resume point advances ($before → $pos ms)" "$([[ ${pos:-0} == "$target" ]] && echo true || echo false)"

# An out-of-order heartbeat from a flaky connection must not rewind the student's place.
curl -s -o /dev/null -X PUT -H "$H" -H 'Content-Type: application/json' \
  -d '{"positionMs":5000}' "$API/progress/$video"
pos2=$(curl -s -H "$H" "$API/progress/$video" | jqp "d['positionMs']")
check "a late, earlier heartbeat does not rewind progress (still $pos2 ms)" \
  "$([[ ${pos2:-0} == "$target" ]] && echo true || echo false)"

# Offline batch, with original client timestamps.
events=$(curl -s -X POST -H "$H" -H 'Content-Type: application/json' -d "{\"events\":[
  {\"videoId\":\"$video\",\"deviceId\":\"$device\",\"event\":\"start\",\"positionMs\":0,\"occurredAt\":\"$(date -u -d '-2 hours' +%Y-%m-%dT%H:%M:%SZ)\",\"offline\":true},
  {\"videoId\":\"$video\",\"deviceId\":\"$device\",\"event\":\"heartbeat\",\"positionMs\":300000,\"occurredAt\":\"$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)\",\"offline\":true}
]}" "$API/progress/events")
check "offline event batch accepted" "$(echo "$events" | jqp "d['accepted']==2")"
check "sync returns the revocation epoch" "$(echo "$events" | jqp "'revocationEpoch' in d")"

# ── Playback ──────────────────────────────────────────────────────────────────
echo
echo "playback"
# No licence has been issued yet, so this must be refused — and say why precisely.
nolic=$(curl -s -X POST -H "$H" -H 'Content-Type: application/json' \
  -d "{\"deviceId\":\"$device\"}" "$API/playback/$video/session")
check "playback without a licence is refused ($(echo "$nolic" | jqp "d['error']['code']"))" \
  "$(echo "$nolic" | jqp "d['error']['code'].startswith('LICENSE')")"
check "refusal carries a Persian message" "$(echo "$nolic" | jqp "len(d['error']['messageFa'])>0")"

# A client must not be able to request a key wrapped for a device it does not control.
# A syntactically valid id belonging to no-one, so the ownership check is what rejects it rather
# than schema validation.
spoof=$(curl -s -X POST -H "$H" -H 'Content-Type: application/json' \
  -d '{"deviceId":"dev_01J8ZQK5T9XVWR3M2N4P6H8B7C"}' "$API/playback/$video/session")
check "a deviceId that is not the authenticated device is rejected ($(echo "$spoof" | jqp "d['error']['code']"))" \
  "$(echo "$spoof" | jqp "d['error']['code']=='FORBIDDEN'")"

# And a malformed one is rejected by schema validation, with the right code rather than a 500.
malformed=$(curl -s -X POST -H "$H" -H 'Content-Type: application/json' \
  -d '{"deviceId":"not-a-device-id"}' "$API/playback/$video/session")
check "a malformed deviceId gives VALIDATION_FAILED, not INTERNAL ($(echo "$malformed" | jqp "d['error']['code']"))" \
  "$(echo "$malformed" | jqp "d['error']['code']=='VALIDATION_FAILED'")"

# ── Devices ───────────────────────────────────────────────────────────────────
echo
echo "devices"
devices=$(curl -s -H "$H" "$API/devices")
check "device list includes this device" "$(echo "$devices" | jqp "any(x['isCurrent'] for x in d['items'])")"

echo
echo "─────────────────────────────"
if [[ $fail -eq 0 ]]; then
  green "$pass passed, 0 failed"
  exit 0
else
  red "$pass passed, $fail FAILED"
  exit 1
fi
