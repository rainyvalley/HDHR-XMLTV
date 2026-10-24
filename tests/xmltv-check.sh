#!/bin/sh
# Checks for what fetch-guide.sh accepts and logs:
#   - a download cut off before </tv> is rejected and the old guide kept
#   - counts in the log are tags, not lines (one-line XMLTV: 5 channels, 7 programmes)
#   - a tuner DeviceID with a newline or escape cannot forge a log line
#   - API_BASE must be https (localhost http is allowed for the mock)
#   - retry delay doubles from 15 min and is capped at 6 h
# Needs MOCK_URL pointing at a running tests/mock_server.py.
: "${MOCK_URL:?set MOCK_URL to the mock server base URL}"
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/fetch-guide.sh"
rc=0
fail() { echo "FAIL: $*"; rc=1; }
run() { # run <data dir> <api suffix> <tuner suffix> [env...]
  d=$1; api=$MOCK_URL$2; dev=$MOCK_URL$3; shift 3
  env RUN_ONCE=1 DEVICE_IP=192.0.2.50 DEVICE_URL="$dev" API_BASE="$api" DATA_DIR="$d" "$@" sh "$SCRIPT" 2>&1
}

# truncated download
D=$(mktemp -d); mkdir "$D/www"
printf '%s\n' '<tv><channel id="1"/></tv>' > "$D/www/guide.xml"; cp "$D/www/guide.xml" "$D/expected"
if out=$(run "$D" /trunc ""); then fail "truncated XMLTV accepted"; fi
cmp "$D/www/guide.xml" "$D/expected" || fail "guide replaced by truncated download"
rm -rf "$D"

# counts on a one-line file
D=$(mktemp -d)
out=$(run "$D" /mini "") || fail "one-line XMLTV rejected: $out"
echo "$out" | grep -q '5 channels, 7 programmes' || fail "wrong counts: $out"
rm -rf "$D"

# forged DeviceID
D=$(mktemp -d)
out=$(run "$D" "" /evilid)
echo "$out" | grep -q '^FORGED' && fail "DeviceID newline forged a log line"
printf '%s' "$out" | LC_ALL=C grep -q "$(printf '[\001-\010\013-\037]')" && fail "raw control characters in log"
echo "$out" | grep -q 'tuner DeviceID=FAKE' || fail "DeviceID not logged: $out"
rm -rf "$D"

# https only
D=$(mktemp -d)
if out=$(env RUN_ONCE=1 DEVICE_IP=192.0.2.50 DEVICE_URL="$MOCK_URL" API_BASE="http://192.0.2.1" DATA_DIR="$D" sh "$SCRIPT" 2>&1); then
  fail "plain http API_BASE accepted"
fi
echo "$out" | grep -q 'API_BASE must start with https://' || fail "no https error: $out"
rm -rf "$D"

# retry delay
fn=$(mktemp)
sed -n '/^retry_delay()/,/^}/p' "$SCRIPT" > "$fn"
# shellcheck disable=SC1090
. "$fn"
rm -f "$fn"
got=$(for n in 1 2 3 4 5 6 20; do retry_delay $n; done | tr '\n' ' ')
[ "$got" = "900 1800 3600 7200 14400 21600 21600 " ] || fail "retry delays: $got"
exit $rc
