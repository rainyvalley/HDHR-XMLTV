#!/bin/sh
# DeviceAuth must reach the API (the mock answers 403 otherwise) without ever
# appearing on a curl command line, where ps / /proc/<pid>/cmdline expose it.
# A curl shim on PATH records every argv and then runs the real curl.
# Needs MOCK_URL pointing at a running tests/mock_server.py.
: "${MOCK_URL:?set MOCK_URL to the mock server base URL}"
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/fetch-guide.sh"
REAL_CURL="$(command -v curl)" || { echo "curl not found"; exit 1; }
TOKEN="$(curl -fsS "$MOCK_URL/discover.json" | jq -r .DeviceAuth)"
[ -n "$TOKEN" ] || { echo "mock server returned no DeviceAuth"; exit 1; }

W=$(mktemp -d)
mkdir "$W/bin" "$W/data"
cat > "$W/bin/curl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$W/argv"
exec "$REAL_CURL" "\$@"
EOF
chmod +x "$W/bin/curl"

rc=0
if ! PATH="$W/bin:$PATH" RUN_ONCE=1 DEVICE_URL="$MOCK_URL" API_BASE="$MOCK_URL" \
     DATA_DIR="$W/data" sh "$SCRIPT"; then
  echo "fetch failed (DeviceAuth not delivered to the API?)"; rc=1
elif ! grep -q '<programme' "$W/data/guide.xml"; then
  echo "no guide published"; rc=1
fi
if grep -qF "$TOKEN" "$W/argv"; then
  echo "DeviceAuth leaked into curl argv:"; cat "$W/argv"; rc=1
fi
rm -rf "$W"
exit $rc
