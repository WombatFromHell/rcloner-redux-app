#!/usr/bin/env bash
set -euo pipefail

HOST_UID=${HOST_UID:-1000}
HOST_GID=${HOST_GID:-1000}

# align our ownership on the containing bind-mount folders
mkdir -p /app/logs /app/locks /synctarget &&
  chown -R "${HOST_UID}:${HOST_GID}" /app/logs /app/locks /app/rclone /app/.cache /synctarget

crond

tail -f /dev/null # keep container running
