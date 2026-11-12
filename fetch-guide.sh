#!/bin/sh
# Pull DeviceAuth from an HDHomeRun on the LAN, download the SiliconDust XMLTV
# guide, and publish it as $DATA_DIR/www/guide.xml (served over HTTP by busybox
# httpd; only the www/ subdirectory is served).
#
# Env:
#   DEVICE_IP   tuner address                         (REQUIRED unless DEVICE_URL is set)
#   DEVICE_URL  tuner base URL, overrides DEVICE_IP   (default http://$DEVICE_IP)
#   PORT        HTTP port to serve www/ on (>1024)    (default 8088)
#   SERVE       1 = start httpd, 0 = don't            (default 1)
#   RUN_ONCE    1 = fetch once (forced) and exit      (default 0)
#   API_BASE    SiliconDust API base URL, https only  (default https://api.hdhomerun.com)
#               (plain http is accepted only for localhost/127.0.0.1, for tests)
#   DATA_DIR    state directory                       (default /data)
#   MAX_FILESIZE  max XMLTV download in bytes         (default 268435456)

DEVICE_IP="${DEVICE_IP:-}"
PORT="${PORT:-8088}"
SERVE="${SERVE:-1}"
RUN_ONCE="${RUN_ONCE:-0}"
API_BASE="${API_BASE:-https://api.hdhomerun.com}"
DATA_DIR="${DATA_DIR:-/data}"
MAX_FILESIZE="${MAX_FILESIZE:-268435456}"
# Only WWW_DIR is served. Temp files live in TMP_DIR, a sibling on the same
# filesystem (the final mv is a rename), never web-visible.
WWW_DIR="$DATA_DIR/www"
TMP_DIR="$DATA_DIR/.tmp"
OUT="$WWW_DIR/guide.xml"
if [ -z "${DEVICE_URL:-}" ]; then
  if [ -z "$DEVICE_IP" ]; then
    echo "ERROR: DEVICE_IP is not set - set DEVICE_IP to your HDHomeRun's address" >&2
    exit 1
  fi
  DEVICE_URL="http://$DEVICE_IP"
fi

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

# DeviceAuth goes to API_BASE in the query string, so it must be https.
# Plain http is allowed only for localhost (the test mock).
case "$API_BASE" in
  https://*|http://127.0.0.1|http://127.0.0.1[:/]*|http://localhost|http://localhost[:/]*) ;;
  *) log "ERROR: API_BASE must start with https://"; exit 1 ;;
esac

# Wait before the next try after a failed fetch: 15, 30, 60, 120, 240 min,
# capped at 6 h. $1 is the number of failures so far (1 or more).
retry_delay() {
  d=900; n=$1
  while [ "$n" -gt 1 ] && [ "$d" -lt 21600 ]; do d=$((d * 2)); n=$((n - 1)); done
  [ "$d" -gt 21600 ] && d=21600
  echo "$d"
}

# Sleep $1 seconds in short slices; restart httpd if it has died.
nap() {
  left=$1
  while [ "$left" -gt 0 ]; do
    n=60; [ "$left" -lt 60 ] && n=$left
    sleep "$n"; left=$((left - n))
    check_httpd
  done
}

fetch() {
  info=$(curl -fsS --max-time 15 --max-filesize 1048576 "$DEVICE_URL/discover.json") || { log "ERROR: can't reach tuner at $DEVICE_URL"; return 1; }
  id=$(printf '%s' "$info" | jq -r '.DeviceID // empty')
  auth=$(printf '%s' "$info" | jq -r '.DeviceAuth // empty')
  [ -n "$auth" ] || { log "ERROR: no DeviceAuth in discover.json"; return 1; }
  # untrusted: printable ASCII only and short
  id=$(printf '%s' "$id" | LC_ALL=C tr -c ' -~' '?' | head -c 64)
  log "tuner DeviceID=$id, got DeviceAuth (${#auth} chars)"

  tmp=$(mktemp "$TMP_DIR/guide.XXXXXX") || { log "ERROR: can't create temp file in $TMP_DIR"; return 1; }
  # --data-urlencode via -G: DeviceAuth can contain characters that need encoding.
  # Fed on stdin (name@-) so the token never appears in curl's argv, which
  # any user on the host can read via ps / /proc/<pid>/cmdline.
  printf '%s' "$auth" | curl -fsS --compressed --max-time 300 --max-filesize "$MAX_FILESIZE" -G "$API_BASE/api/xmltv" \
       --data-urlencode "DeviceAuth@-" -o "$tmp" \
    || { log "ERROR: XMLTV download failed"; rm -f "$tmp"; return 1; }

  # one pass over the file: sanity check so a bad response never replaces a
  # good guide, plus the channel/programme counts for the log
  # A complete file ends with </tv>; a download cut short does not.
  has_end=0
  tail -c 200 "$tmp" | grep -q '</tv>' && has_end=1
  # Counts are tags, not lines, so a one-line (minified) file counts right.
  read -r has_tv chans progs <<EOF
$(awk '/<tv[ >]/{t=1}{c+=gsub(/<channel[ >]/,"&");p+=gsub(/<programme[ >]/,"&")}END{print t+0, c+0, p+0}' "$tmp")
EOF
  if [ "$has_tv" -eq 0 ] || [ "$progs" -eq 0 ] || [ "$has_end" -eq 0 ]; then
    log "ERROR: response doesn't look like complete XMLTV, keeping old guide"
    # untrusted bytes: printable ASCII only, short
    head -c 300 "$tmp" | LC_ALL=C tr -c ' -~' '?'; echo
    rm -f "$tmp"; return 1
  fi
  # mktemp makes 0600; the guide is public (served over HTTP) and must be readable by
  # other uids, e.g. a bind-mount inspected from the host
  chmod 0644 "$tmp" || { log "ERROR: could not chmod temp file, keeping old guide"; rm -f "$tmp"; return 1; }
  mv "$tmp" "$OUT" || { log "ERROR: could not publish $OUT, keeping old guide"; rm -f "$tmp"; return 1; }
  log "published $OUT ($(wc -c < "$OUT") bytes, $chans channels, $progs programmes)"
}

mkdir -p "$WWW_DIR" "$TMP_DIR" || { log "ERROR: can't create directories under $DATA_DIR"; exit 1; }
# A guide.xml left directly in DATA_DIR is moved into the served directory so
# the freshness check still sees it.
if [ -f "$DATA_DIR/guide.xml" ] && [ ! -e "$OUT" ]; then
  mv "$DATA_DIR/guide.xml" "$OUT" && log "moved legacy guide.xml into $WWW_DIR"
fi
# Drop temp files orphaned by a crash (older than a day; never a live fetch)
find "$TMP_DIR" -name 'guide.*' -mmin +1440 -exec rm -f {} + 2>/dev/null

if [ "$RUN_ONCE" = "1" ]; then
  fetch; exit $?
fi

# httpd runs as a background job (-f keeps it in the foreground of that job) so
# we know its PID and can restart it if it dies.
start_httpd() {
  $HTTPD -f -p "$PORT" -h "$WWW_DIR" &
  HTTPD_PID=$!
  sleep 1
  kill -0 "$HTTPD_PID" 2>/dev/null
}
check_httpd() {
  [ "$SERVE" = "1" ] || return 0
  kill -0 "$HTTPD_PID" 2>/dev/null && return 0
  log "WARNING: HTTP server stopped, restarting"
  start_httpd || log "ERROR: HTTP server did not restart, will try again"
}

if [ "$SERVE" = "1" ]; then
  # Alpine ships httpd in busybox-extras, not in the base busybox
  if command -v httpd >/dev/null 2>&1; then HTTPD="httpd"
  elif command -v busybox-extras >/dev/null 2>&1; then HTTPD="busybox-extras httpd"
  else HTTPD=""; fi
  if [ -n "$HTTPD" ] && start_httpd; then
    log "serving $WWW_DIR on :$PORT  ->  http://<host>:$PORT/guide.xml"
  else
    log "ERROR: could not start the HTTP server (is PORT $PORT free and above 1024?)"
    exit 1
  fi
fi

fails=0
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
    fails=$((fails + 1)); r=$(retry_delay "$fails")
    log "retrying in $((r / 60)) min"; nap "$r"; continue
  else
    fails=0
  fi
  log "next fetch in $s s"
  nap "$s"
done
