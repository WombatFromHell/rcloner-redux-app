#!/usr/bin/env bash

SCRIPT_PATH="/app/sync.sh"

HOST_UID=${HOST_UID:-1000}
USERNAME=$(getent passwd "${HOST_UID}" | cut -d: -f1)

detect_su() {
  local su_bin
  if su_bin="$(command -v gosu 2>/dev/null)"; then
    echo "$su_bin"
  elif su_bin="$(command -v sudo 2>/dev/null)"; then
    echo "$su_bin"
  else
    return 1 # not found
  fi
}

main() {
  local SU_BIN
  SU_BIN="$(detect_su)" || {
    echo "Error: 'gosu' or 'sudo' not found" >&2
    return 1
  }

  local ARGS=("$@")
  local SCRIPT_CMD=("$SU_BIN" "$USERNAME" "$SCRIPT_PATH" "${ARGS[@]}")
  echo "Running: ${SCRIPT_CMD[*]}"

  if "${SCRIPT_CMD[@]}"; then
    return 0 # success
  else
    return 1 # failure
  fi
}

if ! main "$@"; then
  exit $?
fi
