FROM alpine:latest

WORKDIR /app

RUN echo "https://dl-cdn.alpinelinux.org/alpine/latest-stable/community" >> /etc/apk/repositories && \
  apk update && \
  apk add --no-cache dcron bash gosu rclone tini tzdata shadow

# Create a placeholder user/group; entrypoint will realign UID/GID at runtime
RUN addgroup -S appgroup && adduser -S -G appgroup -h /app appuser

COPY ./app/bin/entrypoint.sh /app/entrypoint.sh
COPY ./app/crontabs /etc/crontabs/
COPY ./app/bin/sync.sh ./app/bin/sync_task.sh /app/

RUN chmod 0755 /app/entrypoint.sh && \
  mkdir -p /etc/crontabs && \
  chmod 0600 /etc/crontabs/* && \
  chmod 0755 /app/sync.sh /app/sync_task.sh

# stay root at build time — entrypoint drops privileges at runtime
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/entrypoint.sh"]
