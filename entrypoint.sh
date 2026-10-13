#!/bin/sh
# Container entrypoint. Started as root (the default), fix ownership of the
# data volume so volumes created by older root-running versions keep working,
# then drop to the unprivileged app user. Started as any other uid (compose
# `user:` / docker run --user), just run the fetcher as that uid.
DATA_DIR="${DATA_DIR:-/data}"
APP_UID=10001   # keep in sync with the Dockerfile
APP_GID=10001

# Fail fast, before any chown/privilege drop. DEVICE_URL is an alternative.
if [ -z "${DEVICE_IP:-}" ] && [ -z "${DEVICE_URL:-}" ]; then
  echo "ERROR: DEVICE_IP is not set - set DEVICE_IP to your HDHomeRun's address" >&2
  exit 1
fi

if [ "$(id -u)" = "0" ]; then
  mkdir -p "$DATA_DIR" || exit 1
  chown -R "$APP_UID:$APP_GID" "$DATA_DIR" || { echo "ERROR: can't chown $DATA_DIR" >&2; exit 1; }
  # busybox su (no setpriv uid switch / su-exec in the image); the app user has
  # a nologin shell, so name a shell explicitly. Environment is preserved.
  exec su -s /bin/sh app -c "exec /fetch-guide.sh"
fi
exec /fetch-guide.sh "$@"
