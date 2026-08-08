FROM alpine:latest

WORKDIR /app

RUN echo "https://dl-cdn.alpinelinux.org/alpine/latest-stable/community" >> /etc/apk/repositories && \
  apk update && \
  apk add --no-cache dcron bash rclone tini tzdata shadow

COPY ./app/bin/entrypoint.sh /app/entrypoint.sh
COPY ./app/bin/sync.sh /app/
COPY ./app/bin/user-secrets.sh /app/

RUN chmod 0755 /app/entrypoint.sh && \
  chmod 0755 /app/sync.sh /app/user-secrets.sh

# stay root at runtime — entrypoint creates per-user accounts and crontabs,
# and crond must run as root to switch to each user's job identity
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/entrypoint.sh"]
