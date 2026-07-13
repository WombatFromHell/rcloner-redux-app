#!/usr/bin/env bash
set -euo pipefail

PUID=${PUID:-1000}
PGID=${PGID:-1000}
TZ=${TZ:-UTC}

# Set timezone
if [ -f "/usr/share/zoneinfo/${TZ}" ]; then
  ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
  echo "${TZ}" >/etc/timezone
else
  echo "WARNING: unknown TZ '${TZ}', falling back to UTC" >&2
  ln -sf /usr/share/zoneinfo/UTC /etc/localtime
  echo "UTC" >/etc/timezone
fi

# Realign appgroup/appuser to the requested runtime PGID/PUID
if ! getent group "${PGID}" >/dev/null; then
  groupmod -o -g "${PGID}" appgroup
fi
if ! getent passwd "${PUID}" >/dev/null; then
  usermod -o -u "${PUID}" appuser
fi

mkdir -p /app/logs /app/locks /synctarget
chown -R "${PUID}:${PGID}" /app /synctarget
chown appuser:appgroup /etc/crontabs/appuser

crond
exec gosu appuser tail -f /dev/null
