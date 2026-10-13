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
  # --data-urlencode via -G: DeviceAuth can contain characters that need encoding.
  # Fed on stdin (name@-) so the token never appears in curl's argv, which
  # any user on the host can read via ps / /proc/<pid>/cmdline.
  printf '%s' "$auth" | curl -fsS --compressed --max-time 300 -G "$API_BASE/api/xmltv" \
       --data-urlencode "DeviceAuth@-" -o "$tmp" \
    || { log "ERROR: XMLTV download failed"; rm -f "$tmp"; return 1; }

  # one pass over the file: sanity check so a bad response never replaces a
  # good guide, plus the channel/programme counts for the log
  read -r has_tv chans progs <<EOF
$(awk '/<tv/{t=1}/<channel /{c++}/<programme/{p++}END{print t+0, c+0, p+0}' "$tmp")
EOF
  if [ "$has_tv" -eq 0 ] || [ "$progs" -eq 0 ]; then
    log "ERROR: response doesn't look like XMLTV, keeping old guide"
    head -c 300 "$tmp"; echo
    rm -f "$tmp"; return 1
  fi
  mv "$tmp" "$OUT"
  log "published $OUT ($(wc -c < "$OUT") bytes, $chans channels, $progs programmes)"
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
    exit 1
  fi
fi

while true; do
  # SiliconDust asks for randomized 20-28h between requests
  s=$(awk 'BEGIN{srand(); print int(72000 + rand()*28800)}')
  # skip the fetch on restart if the file is fresher than 20h, but
  # subtract its age so the gap stays in the 20-28h window. A future mtime
  # (clock skew, restored volume) counts as stale: otherwise its negative
  # age would push the next fetch out by however far ahead it is.
  age=-1
  [ -s "$OUT" ] && age=$(( $(date +%s) - $(stat -c %Y "$OUT") ))
  if [ "$age" -ge 0 ] && [ "$age" -lt 72000 ]; then
    s=$(( s - age ))
    log "guide.xml is less than 20h old, next fetch in $s s"
  elif ! fetch; then
    log "retrying in 15 min"; sleep 900; continue
  fi
  log "next fetch in $s s"
  sleep "$s"
done
