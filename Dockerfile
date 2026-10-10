FROM alpine:3.20
# hadolint ignore=DL3018
# Versions deliberately unpinned: the v3.20 index keeps moving past EOL, so a
# pin that exists today would break when alpine rebuilds any of these.
RUN apk add --no-cache curl jq busybox-extras tzdata
COPY --chmod=0755 fetch-guide.sh /fetch-guide.sh
VOLUME /data
EXPOSE 8088
ENTRYPOINT ["/fetch-guide.sh"]
