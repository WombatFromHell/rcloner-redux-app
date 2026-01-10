FROM alpine:latest

# Use host user's UID/GID (passed at build time)
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG TZ=UTC
#
ENV HOST_UID=${HOST_UID}
ENV HOST_GID=${HOST_GID}

# Enable Community repo and install dependencies
RUN echo "https://dl-cdn.alpinelinux.org/alpine/latest-stable/community" >> /etc/apk/repositories && \
  apk update && \
  apk add --no-cache dcron bash gosu rclone tini tzdata && \
  ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && \
  echo "${TZ}" > /etc/timezone

WORKDIR /app

# Align appuser/appgroup with the HOST_UID/HOST_GID
RUN set -eux; \
  if getent group ${HOST_GID} >/dev/null; then \
  APP_GRP="$(getent group ${HOST_GID} | cut -d: -f1)"; \
  else \
  addgroup -g ${HOST_GID} -S appgroup; \
  APP_GRP=appgroup; \
  fi; \
  \
  if getent passwd ${HOST_UID} >/dev/null; then \
  echo "UID ${HOST_UID} already exists" >&2; exit 1; \
  fi; \
  \
  chown -R ${HOST_UID}:${HOST_GID} /app && \
  adduser -u ${HOST_UID} -S -G "${APP_GRP}" -h /app appuser

# Copy scripts and set permissions
COPY ./app/bin/entrypoint.sh /root/entrypoint.sh
RUN chmod 0755 /root/entrypoint.sh

# Ensure permissions of crontab are correct
RUN mkdir -p /etc/crontabs
COPY ./app/crontabs /etc/crontabs/
RUN chmod 0600 /etc/crontabs/*

COPY ./app/bin/sync.sh ./app/bin/sync_task.sh /app/
RUN chmod 0755 /app/sync.sh && \
  chown ${HOST_UID}:${HOST_GID} /app/sync.sh /app/sync_task.sh

# Set tini as init
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/root/entrypoint.sh"]
