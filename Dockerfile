# Alpine 3.24, pinned by digest. Bump tag and digest together
# (docker pull alpine:3.24; docker images --digests alpine).
FROM alpine:3.24@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a
# hadolint ignore=DL3018
# Package versions are not pinned; the base image is pinned instead.
RUN apk add --no-cache curl jq busybox-extras tzdata \
 && addgroup -g 10001 -S app \
 && adduser -u 10001 -S -D -H -G app -s /sbin/nologin app
COPY --chmod=0755 fetch-guide.sh entrypoint.sh /
VOLUME /data
# Unprivileged port (>1024), so httpd needs no root.
EXPOSE 8088
# Healthy when httpd answers with the published guide. Not healthy until the
# first fetch has worked. With SERVE=0 there is no server to ask.
HEALTHCHECK --interval=60s --timeout=5s --start-period=120s --retries=3 \
  CMD [ "${SERVE:-1}" = "0" ] || wget -q -O /dev/null "http://127.0.0.1:${PORT:-8088}/guide.xml" || exit 1
# Starts as root only to chown /data and then drops to uid 10001 (busybox su); see entrypoint.sh.
ENTRYPOINT ["/entrypoint.sh"]
