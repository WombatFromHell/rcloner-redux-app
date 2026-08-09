#!/bin/sh
# Container healthcheck: exit 0 (healthy) only if every pipeline's
# .healthcheck file is healthy AND recent. A stale file means the sync
# silently stopped running. No files yet = no signal = healthy.
# ponytail: one global HEALTH_MAX_AGE; parsing per-remote dcron schedules is
# not worth it. Raise HEALTH_MAX_AGE for crons slower than the default.
max_age="${HEALTH_MAX_AGE:-7200}"
now=$(date +%s)
for f in "${HEALTH_DIR:-/app/logs}"/*/.healthcheck-*; do
  [ -f "$f" ] || continue
  status=$(sed -n 's/^STATUS=//p' "$f")
  last=$(sed -n 's/^LAST_RUN=//p' "$f")
  if [ "$status" = degraded ] || { [ -n "$last" ] && [ $((now - last)) -gt "$max_age" ]; }; then
    echo "degraded/stale: $f"
    exit 1
  fi
done
exit 0
