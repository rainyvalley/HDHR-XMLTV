#!/bin/sh
# Output layout and hardening checks for fetch-guide.sh:
#   - the published guide is the only file in the served directory (www/),
#     temp files live outside it and are cleaned up
#   - a guide.xml left in DATA_DIR by older versions is moved into www/
#   - MAX_FILESIZE rejects an oversized download and keeps the old guide
#   - untrusted response bytes are sanitised before they reach the log
# Needs MOCK_URL pointing at a running tests/mock_server.py.
: "${MOCK_URL:?set MOCK_URL to the mock server base URL}"
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/fetch-guide.sh"
rc=0
fail() { echo "FAIL: $*"; rc=1; }
run() { # run <data dir> [api suffix] [extra env assignments...]
  d=$1; api=$MOCK_URL$2; shift 2
  env RUN_ONCE=1 DEVICE_URL="$MOCK_URL" API_BASE="$api" DATA_DIR="$d" "$@" sh "$SCRIPT" 2>&1
}

D=$(mktemp -d)
printf '%s\n' '<tv><channel id="1.1"><display-name>legacy</display-name></channel></tv>' > "$D/guide.xml"
out=$(run "$D" "") || fail "fetch failed: $out"
grep -q '<programme' "$D/www/guide.xml" || fail "guide not published to www/"
[ ! -e "$D/guide.xml" ] || fail "legacy guide.xml left behind in DATA_DIR"
echo "$out" | grep -q 'moved legacy' || fail "legacy migration not logged"
[ "$(ls -A "$D/www")" = "guide.xml" ] || fail "www/ holds more than guide.xml: $(ls -A "$D/www")"
[ -z "$(ls -A "$D/.tmp")" ] || fail "temp files left in .tmp: $(ls -A "$D/.tmp")"
[ "$(stat -c %a "$D/www/guide.xml")" = 644 ] || fail "guide.xml mode is $(stat -c %a "$D/www/guide.xml"), want 644"

# oversized download: rejected, previous guide untouched
cp "$D/www/guide.xml" "$D/expected"
if out=$(run "$D" "" MAX_FILESIZE=100); then fail "oversized download accepted"; fi
cmp "$D/www/guide.xml" "$D/expected" || fail "guide changed after oversized download"
[ -z "$(ls -A "$D/.tmp")" ] || fail "temp left after oversized download"

# unwritable destination: mv failure must not be logged as success
chmod 555 "$D/www"
if [ "$(id -u)" != 0 ]; then
  if out=$(run "$D" ""); then fail "success reported although mv failed"; fi
  echo "$out" | grep -q 'published' && fail "'published' logged although mv failed"
  [ -z "$(ls -A "$D/.tmp")" ] || fail "temp left after failed mv"
fi
chmod 755 "$D/www"
rm -rf "$D"

# control bytes in a bad response never reach the log raw
D=$(mktemp -d)
out=$(run "$D" "/ctrl") && fail "control-byte response accepted"
if printf '%s' "$out" | LC_ALL=C grep -q "$(printf '[\001-\010\013-\037]')"; then
  fail "raw control characters in log output"
fi
echo "$out" | grep -q 'EVIL' || fail "sanitised response preview missing"
rm -rf "$D"
exit $rc
