#!/usr/bin/env bash
# Load a per-user per-remote secrets file (/run/secrets/<user>-<remote>,
# KEY=VAL lines) into the environment as <USER>_SRC_DIR / <USER>_TGT_DIR,
# <REMOTE>_RCLONE_OPTS, and RCLONE_CONFIG_<REMOTE>_<KEY> for every other key
# (TYPE, CLIENT_ID, CLIENT_SECRET, TOKEN, SCOPE, ...). One file per remote per
# user, e.g. "bob-gdrive" -> remote "gdrive"; the remote name is the filename
# suffix and must be env-safe ([A-Za-z0-9_]). No-op when the file is absent or
# unreadable. See secrets/*.example.
load_user_secrets() {
  local user="$1" remote="${2^^}"
  local file="/run/secrets/${user}-${2}"
  [[ -r "$file" ]] || return 0
  if [[ ! "$remote" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "ERROR: [secrets/${user}-${remote}] remote name '${remote}' must be env-safe ([A-Za-z0-9_] only); rclone config is built from env vars, which cannot hold '-' or other characters" >&2
    return 1
  fi
  local upuser="${user^^}"
  local line key val
  local -a lines=()
  while IFS= read -r line; do
    lines+=("$line")
  done < "$file"
  RCLONE_REMOTE="$remote"
  for line in "${lines[@]}"; do
    [[ "$line" == *=* && "$line" != \#* ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    if [[ "$key" == SRC_DIR || "$key" == TGT_DIR ]]; then
      export "${upuser}_${key}=${val}"
    elif [[ "$key" == RCLONE_OPTS ]]; then
      export "${remote}_RCLONE_OPTS=${val}"
    elif [[ "$key" == CRON ]]; then
      # Strip quotes so `CRON="0 3 * * *"` works; dcron would reject a quoted
      # field. Cron schedules never legitimately contain quotes.
      export "${remote}_CRON=${val//\"}"
    elif [[ "$key" == ENABLED ]]; then
      export "${remote}_ENABLED=${val}"
    elif [[ "$key" != REMOTE_NAME ]]; then
      export "RCLONE_CONFIG_${remote}_${key}=${val}"
    fi
  done
}
