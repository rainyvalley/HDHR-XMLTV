# Alpine 3.24.4, pinned by digest. Bump the tag and the digest together
# (docker pull alpine:3.24; docker buildx imagetools inspect alpine:3.24).
FROM alpine:3.24@sha256:3f4d6b32e26703c6082839234f43769d5046b3ac7c910033911d1e71d8cd630a
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
# Exec form with an explicit shell: the check reads ${SERVE} and ${PORT}.
HEALTHCHECK --interval=60s --timeout=5s --start-period=120s --retries=3 \
  CMD ["/bin/sh", "-c", "[ \"${SERVE:-1}\" = \"0\" ] || wget -q -O /dev/null \"http://127.0.0.1:${PORT:-8088}/guide.xml\""]
# Starts as root only to chown /data and then drops to uid 10001 (busybox su); see entrypoint.sh.
ENTRYPOINT ["/entrypoint.sh"]
