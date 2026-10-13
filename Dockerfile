FROM alpine:3.20
# hadolint ignore=DL3018
# Versions deliberately unpinned: the v3.20 index keeps moving past EOL, so a
# pin that exists today would break when alpine rebuilds any of these.
RUN apk add --no-cache curl jq busybox-extras tzdata \
 && addgroup -g 10001 -S app \
 && adduser -u 10001 -S -D -H -G app -s /sbin/nologin app
COPY --chmod=0755 fetch-guide.sh entrypoint.sh /
VOLUME /data
# Unprivileged port (>1024), so httpd needs no root.
EXPOSE 8088
# Starts as root only to chown /data and then drops to uid 10001 (busybox su); see entrypoint.sh.
ENTRYPOINT ["/entrypoint.sh"]
