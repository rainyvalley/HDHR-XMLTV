#!/bin/sh
# Pull DeviceAuth from an HDHomeRun on the LAN, download the SiliconDust XMLTV
# guide, and publish it as /data/guide.xml (served over HTTP by busybox httpd).
#
# Env:
#   DEVICE_IP   tuner address                         (default 192.168.3.193)
#   PORT        HTTP port to serve /data on           (default 8088)
#   SERVE       1 = start httpd, 0 = don't            (default 1)
#   RUN_ONCE    1 = fetch once (forced) and exit      (default 0)
#   API_BASE    SiliconDust API base URL              (default https://api.hdhomerun.com)
#   DATA_DIR    output directory                      (default /data)

DEVICE_IP="${DEVICE_IP:-192.168.3.193}"
PORT="${PORT:-8088}"
SERVE="${SERVE:-1}"
RUN_ONCE="${RUN_ONCE:-0}"
API_BASE="${API_BASE:-https://api.hdhomerun.com}"
DATA_DIR="${DATA_DIR:-/data}"
OUT="$DATA_DIR/guide.xml"
DEVICE_URL="${DEVICE_URL:-http://$DEVICE_IP}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

fetch() {
  info=$(curl -fsS --max-time 15 "$DEVICE_URL/discover.json") || { log "ERROR: can't reach tuner at $DEVICE_URL"; return 1; }
  id=$(printf '%s' "$info" | jq -r '.DeviceID // empty')
  auth=$(printf '%s' "$info" | jq -r '.DeviceAuth // empty')
  [ -n "$auth" ] || { log "ERROR: no DeviceAuth in discover.json"; return 1; }
  log "tuner DeviceID=$id, got DeviceAuth (${#auth} chars)"

  tmp="$OUT.tmp"
  # --data-urlencode via -G: DeviceAuth can contain characters that need encoding
  curl -fsS --compressed --max-time 300 -G "$API_BASE/api/xmltv" \
       --data-urlencode "DeviceAuth=$auth" -o "$tmp" \
    || { log "ERROR: XMLTV download failed"; rm -f "$tmp"; return 1; }

  # sanity check so a bad response never replaces a good guide
  if ! grep -q '<tv' "$tmp" || ! grep -q '<programme' "$tmp"; then
    log "ERROR: response doesn't look like XMLTV, keeping old guide"
    head -c 300 "$tmp"; echo
    rm -f "$tmp"; return 1
  fi
  mv "$tmp" "$OUT"
  log "published $OUT ($(wc -c < "$OUT") bytes, $(grep -c '<channel ' "$OUT") channels, $(grep -c '<programme' "$OUT") programmes)"
}

mkdir -p "$DATA_DIR"

if [ "$RUN_ONCE" = "1" ]; then
  fetch; exit $?
fi

if [ "$SERVE" = "1" ]; then
  # Alpine ships httpd in busybox-extras, not in the base busybox
  if command -v httpd >/dev/null 2>&1; then HTTPD="httpd"
  elif command -v busybox-extras >/dev/null 2>&1; then HTTPD="busybox-extras httpd"
  else HTTPD=""; fi
  if [ -n "$HTTPD" ] && $HTTPD -p "$PORT" -h "$DATA_DIR"; then
    log "serving $DATA_DIR on :$PORT  ->  http://<host>:$PORT/guide.xml"
  else
    log "ERROR: could not start the HTTP server"
  fi
fi

while true; do
  # skip the fetch on restart if the file is fresher than 20h
  if [ -s "$OUT" ] && [ -n "$(find "$OUT" -mmin -1200 2>/dev/null)" ]; then
    log "guide.xml is less than 20h old, not refetching"
  elif ! fetch; then
    log "retrying in 15 min"; sleep 900; continue
  fi
  # SiliconDust asks for randomized 20-28h between requests
  s=$(awk 'BEGIN{srand(); print int(72000 + rand()*28800)}')
  log "next fetch in $s s"
  sleep "$s"
  # force a refetch after the sleep (file is now >20h old anyway)
done
