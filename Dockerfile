# Alpine 3.23, pinned by digest. Bump tag and digest together
# (docker pull alpine:3.23; docker images --digests alpine).
FROM alpine:3.23@sha256:ff7f0c727dd796aa36787bfcd9a64bf35a6ce72a73451b3359fde849b6703d63
# hadolint ignore=DL3018
# Package versions are not pinned: Alpine removes old package builds from its
# index, so a pin that exists today can break the build tomorrow. The base
# image is pinned instead.
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
