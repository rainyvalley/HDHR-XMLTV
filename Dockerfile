FROM alpine:3.20
RUN apk add --no-cache curl jq
COPY fetch-guide.sh /fetch-guide.sh
RUN chmod +x /fetch-guide.sh
VOLUME /data
EXPOSE 8088
ENTRYPOINT ["/fetch-guide.sh"]
