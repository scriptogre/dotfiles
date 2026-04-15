FROM alpine:3.21

RUN apk add --no-cache busybox-extras coreutils curl jq

COPY server.sh /server.sh
RUN chmod +x /server.sh

COPY checks/ /srv/cgi-bin/
RUN chmod +x /srv/cgi-bin/*.sh

EXPOSE 8080

CMD ["/server.sh"]
