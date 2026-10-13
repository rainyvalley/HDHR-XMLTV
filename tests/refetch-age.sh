#!/bin/sh
# Restart-path checks for the refetch loop (SERVE=0, no RUN_ONCE):
#   - a guide.xml with a future mtime must be refetched, not trusted as fresh
#   - a guide.xml that is 1h old must be kept and not refetched
# Needs MOCK_URL pointing at a running tests/mock_server.py.
: "${MOCK_URL:?set MOCK_URL to the mock server base URL}"
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/fetch-guide.sh"
OLD='<tv><channel id="1.1"><display-name>old-guide</display-name></channel></tv>'

# Run the loop in its own session for a few seconds, then kill the whole
# process group (the loop ends up in a long `sleep`).
run_loop() {
  DATA_DIR="$1" SERVE=0 DEVICE_IP=192.0.2.50 DEVICE_URL="$MOCK_URL" API_BASE="$MOCK_URL" \
    setsid sh "$SCRIPT" > "$1/log" 2>&1 &
  pid=$!
  i=0
  while [ $i -lt 50 ] && ! grep -q 'next fetch in' "$1/log" 2>/dev/null; do
    sleep 0.2; i=$((i + 1))
  done
  kill -- "-$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
}

rc=0

D=$(mktemp -d)
mkdir "$D/www"
printf '%s\n' "$OLD" > "$D/www/guide.xml"
touch -d '+30 days' "$D/www/guide.xml"
run_loop "$D"
if grep -q 'old-guide' "$D/www/guide.xml" || ! grep -q 'published' "$D/log"; then
  echo "future-mtime guide.xml was not refetched:"; cat "$D/log"; rc=1
fi
rm -rf "$D"

D=$(mktemp -d)
mkdir "$D/www"
printf '%s\n' "$OLD" > "$D/www/guide.xml"
touch -d '-1 hour' "$D/www/guide.xml"
run_loop "$D"
if ! grep -q 'old-guide' "$D/www/guide.xml" || ! grep -q 'less than 20h old' "$D/log"; then
  echo "1h-old guide.xml was refetched instead of kept:"; cat "$D/log"; rc=1
fi
rm -rf "$D"

exit $rc
