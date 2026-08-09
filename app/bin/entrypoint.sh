#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source /app/user-secrets.sh

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

# USERS can be set explicitly; otherwise infer it from any <USER>_PUID /
# <USER>_PGID env vars so a manual list is optional.
# ponytail: env-pattern scan; if some unrelated var ever ends in _PUID/_PGID,
# set USERS explicitly to take precedence.
if [[ -z "${USERS:-}" ]]; then
  USERS=""
  for v in $(compgen -e); do
    case "$v" in
      *_PUID | *_PGID)
        u="${v%_PUID}"
        u="${u%_PGID}"
        u="${u,,}"
        case " ${USERS} " in
          *" ${u} "*) ;;
          *) USERS+="${u} " ;;
        esac
        ;;
    esac
  done
fi

# Create one OS account, per-user dirs, and a root-owned crontab per user.
# ponytail: crontab must be root-owned (dcron only loads files whose
# st_uid == crond's uid); dcron still runs each crontab as its named user.
for user in ${USERS:-}; do
  upuser="${user^^}"
  puid_var="${upuser}_PUID"
  pgid_var="${upuser}_PGID"
  puid="${!puid_var:-1000}"
  pgid="${!pgid_var:-1000}"

  # Load this user's secrets into the env so crond's jobs inherit the remote
  # config. The folder mount is read-only; file perms are controlled on the
  # host (keep them 0600). Manual docker exec runs (root) read the file again
  # via load_user_secrets in sync.sh.
  if ! getent group "${pgid}" >/dev/null; then
    addgroup -g "${pgid}" "${user}"
  fi
  group="$(getent group "${pgid}" | cut -d: -f1)"
  if ! getent passwd "${user}" >/dev/null; then
    adduser -D -u "${puid}" -G "${group}" -h /app -s /bin/sh "${user}"
  else
    groupmod -o -g "${pgid}" "$(id -gn "${user}")"
    usermod -o -u "${puid}" -g "${group}" "${user}"
  fi

  src_var="${upuser}_SRC_DIR"
  cron_var="${upuser}_CRON"
  src="${!src_var:-/synctarget/${user}}"
  user_cron="${!cron_var:-*/15 * * * *}"
  mkdir -p "${src}" "/app/logs/${user}" "/app/locks/${user}" "/app/.cache/rclone/${user}"
  chown -R "${puid}:${pgid}" "${src}" "/app/logs/${user}" "/app/locks/${user}" "/app/.cache/rclone/${user}"

  # One crontab entry per remote: the secrets dir holds one file per remote per
  # user, named <user>-<remote> (e.g. bob-gdrive). Skip *.example template
  # files. With no remote file, fall back to a single entry whose remote
  # defaults to the username (env-var-only dev flow).
  remotes=()
  for f in /run/secrets/${user}-*; do
    [[ -e "$f" ]] || continue
    base="${f##*/}"
    [[ "$base" == *.example ]] && continue
    remotes+=("${base#${user}-}")
  done
  if [[ ${#remotes[@]} -eq 0 ]]; then
    printf '%s /app/sync.sh --user %s\n' "${user_cron}" "${user}" > "/etc/crontabs/${user}"
  else
    : > "/etc/crontabs/${user}"
    for remote in "${remotes[@]}"; do
      load_user_secrets "$user" "$remote"
      # ponytail: ENABLED gates only the cron schedule; manual --remote runs
      # still execute. Add a sync.sh guard if manual runs must refuse disabled
      # configs. Falsy is 0/false (case-insensitive); absent defaults to enabled.
      enabled_var="${remote^^}_ENABLED"
      enabled="${!enabled_var:-1}"
      [[ "${enabled,,}" == 0 || "${enabled,,}" == false ]] && {
        # A disabled remote's stale healthcheck would false-positive the
        # container healthcheck; drop it at start.
        rm -f "/app/logs/${user}/.healthcheck-${remote}"
        continue
      }
      cron_var="${remote^^}_CRON"
      printf '%s /app/sync.sh --user %s --remote %s\n' "${!cron_var:-${user_cron}}" "${user}" "${remote}" >> "/etc/crontabs/${user}"
    done
  fi
  chown root:root "/etc/crontabs/${user}"
  chmod 0600 "/etc/crontabs/${user}"
done

# -L logs to a file so container-side failures are visible (no syslog in alpine)
mkdir -p /app/logs
crond -L /app/logs/crond.log
exec tail -f /dev/null
