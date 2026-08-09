# Instructions for `rcloner-redux`

`rcloner` runs one or more rclone bisync jobs in a single container, one per
user. Each user gets their own OS account (realigned to a specified PUID/PGID),
their own rclone remote defined entirely by environment variables, and their
own crontab.

**IMPORTANT!** Copy `compose.env.example` to `compose.env` and edit it for your
use **before proceeding!** Host-side build vars (`IMAGENAME`, `VERSION`,
`APPROOT`, `SYNCTARGET`) also need to be set in `.env` for `build.sh` /
`docker compose` interpolation. Do not commit `compose.env` or `.env` — they
contain tokens/secrets.

### Configuring users

1. In `compose.env`, add each username to `USERS` (space-separated) — or leave
   it empty; the user list is inferred from any `<USER>_PUID`/`<USER>_PGID`
   vars defined below.
2. Per user, fill in a `ALICE_PUID`/`ALICE_PGID` (their host uid/gid), an
   optional `ALICE_CRON` schedule (default `*/15 * * * *`) and optional
   `ALICE_FILTER_FILE`.
3. Per user, create one secrets file **per remote** under `./secrets/` (the
   whole folder is mounted read-only at `/run/secrets`, so its contents never
   show up in `docker inspect`). Name it `<user>-<remote>`, e.g. copy
   `secrets/bob-gdrive.example` to `secrets/bob-gdrive` and fill it in with the
   rclone remote + source/target dirs — the filename suffix after `<user>-`
   IS the rclone remote name:

   ```sh
   TYPE=drive
   CLIENT_ID=...
   CLIENT_SECRET=...
   TOKEN=...
   SCOPE=drive
   SRC_DIR=/synctarget/bob
   TGT_DIR=gdrive:/Backups
   ```

   Generate the token locally first: `rclone config create gdrive drive scope drive`,
   then copy the values from `~/.config/rclone/rclone.conf` into the file. A
   `client_id`/`client_secret` is required for drive service accounts and
   recommended for the OAuth flow so tokens can be refreshed.

   `SRC_DIR`/`TGT_DIR` map to `ALICE_SRC_DIR`/`ALICE_TGT_DIR`; every other key
   maps to `RCLONE_CONFIG_<REMOTE>_<KEY>`. The remote name (the filename suffix)
   must be env-safe: letters/digits/underscore only. **No `rclone.conf` is needed
   inside the container.** Keep host-side file permissions tight (e.g. 0600).

   A user can have several remotes — just add more files (`bob-gdrive`,
   `bob-onedrive`, ...); each becomes its own crontab entry and sync pair.
   A `CRON="..."` key in a secrets file overrides that user's default schedule
   for just that remote; `ENABLED=0` (or `false`) disables a remote's crontab
   entry without deleting the file — manual `--remote` runs still work.

   Per-remote extra rclone flags go in `RCLONE_OPTS` (keyed by the remote, not
   the username), e.g. `RCLONE_OPTS=--fast-list --drive-chunk-size 64M`.

   If no per-user filter file exists, a shared `/app/rclone/filters` file is
   used as a fallback (create it in `app/rclone/` on the host).

### Manual first-run per user

The first sync requires a dry-run, then a real run, to build bisync state.

1. Run `./build.sh -r -s` to build, run, and enter a shell in a test container.
2. From inside the container run `./sync.sh --user alice --first-run` — this
   forces a dry-run and creates a safety lock.
3. Review `app/logs/alice/initial-sync.log`, then run the same command again to
   perform the actual initial bisync.

To deduplicate the remote side, run
`./sync.sh --user alice --remote gdrive --dedup --fast-list --dedupe-mode newest`
— `--dedup` must be the last option; everything after it is passed straight to
`rclone dedupe` on `TGT_DIR`, and no first-run/bisync state is required.
4. The crontab is generated at container start from `ALICE_CRON`; restart the
   container (`docker compose restart`) after changing a schedule.

### Building and running

1. Run `sudo ./build.sh -r` to build and run, or `sudo ./build.sh --stop` to stop.
2. Or use `docker compose up -d` (with `docker-compose.yml` customized as
   needed) for the finished container.

### Portainer/Komodo app setup (follow the instructions above first)

1. Import your customized `.env` file variables.
2. Copy the contents of the `docker-compose.yml` file into your container setup.
3. Remove the `build: ...` section entirely.
4. Ensure the `image: ...` ref matches your `IMAGENAME` tag from the `.env` file.
5. Manually run `sudo ./build.sh -b` command when you want to rebuild/update the container.
6. Redeploy the application and enjoy!

### Logs

- Sync logs: `app/logs/<user>/sync.log` (rotated via `LOG_MAX_SIZE`/`LOG_MAX_BACKUPS`).
- Cron daemon log: `app/logs/crond.log` — check here if a job is not firing.

### Healthcheck

Each sync run writes a state file at `app/logs/<user>/.healthcheck-<remote>`
(`STATUS=degraded` on failure, `STATUS=healthy` on success, plus `LAST_RUN`).
The container's healthcheck runs `/app/healthcheck.sh`: it marks the container
unhealthy if any file is degraded **or** stale (no run for `HEALTH_MAX_AGE`
seconds, default 7200 — raise it for crons slower than the default 15 min),
which catches a sync that silently stopped. Absent files (never run / disabled
remote) count as healthy.
