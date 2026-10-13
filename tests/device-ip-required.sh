#!/bin/sh
# DEVICE_IP has no default: with neither DEVICE_IP nor DEVICE_URL set, both the
# fetcher and the entrypoint must exit non-zero at once with a clear message.
# DEVICE_URL alone is a valid alternative. Needs no mock server.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MSG="set DEVICE_IP to your HDHomeRun's address"
rc=0
fail() { echo "FAIL: $*"; rc=1; }
D=$(mktemp -d)

for s in fetch-guide.sh entrypoint.sh; do
  # entrypoint.sh would exec /fetch-guide.sh; it must fail before that.
  out=$(env -u DEVICE_IP -u DEVICE_URL RUN_ONCE=1 DATA_DIR="$D" sh "$ROOT/$s" 2>&1) \
    && fail "$s: started without DEVICE_IP"
  echo "$out" | grep -qF "$MSG" || fail "$s: message missing, got: $out"
  out=$(env -u DEVICE_URL DEVICE_IP= RUN_ONCE=1 DATA_DIR="$D" sh "$ROOT/$s" 2>&1) \
    && fail "$s: started with empty DEVICE_IP"
  echo "$out" | grep -qF "$MSG" || fail "$s: message missing for empty DEVICE_IP"
done

# DEVICE_URL alone passes the check (the tuner is then unreachable, a different error)
out=$(env -u DEVICE_IP DEVICE_URL=http://127.0.0.1:59999 RUN_ONCE=1 DATA_DIR="$D" sh "$ROOT/fetch-guide.sh" 2>&1)
echo "$out" | grep -qF "$MSG" && fail "DEVICE_URL alone wrongly rejected"

rm -rf "$D"
[ $rc -eq 0 ] && echo "device-ip-required OK"
exit $rc
