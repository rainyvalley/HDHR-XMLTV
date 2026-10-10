FROM alpine:3.20
RUN apk add --no-cache curl jq busybox-extras tzdata
COPY --chmod=0755 fetch-guide.sh /fetch-guide.sh
VOLUME /data
EXPOSE 8088
ENTRYPOINT ["/fetch-guide.sh"]
