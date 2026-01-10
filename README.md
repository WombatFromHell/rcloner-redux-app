# Instructions for `rcloner-redux`

Ensure that you generate a working `./app/rclone/rclone.conf` using a locally installed version of `rclone`.

**IMPORTANT!** Customize the `.env.example` by copying to and editing `.env` for your use, **before proceeding!**

Inspect and customize the `./app/sync.conf` file for `sync.sh` to match your needs.

If you need to alter the bisync filters, edit the `./app/rclone/filters` file.

### Building and manual workflow setup

1. Run `sudo ./build.sh -r -s` to build, run, and enter a shell within a locally installed test container.
2. Run `./sync_task.sh --first-run` to generate a dry-run lock file (safety measure to prevent data loss).
3. Run `./sync_task.sh --first-run` again to actually do a bisync if everything looks good in `./app/logs/initial-sync.log`.
4. Edit the `./app/crontabs/root` file and uncomment the first line to run the sync task every 15 minutes (default).
5. Run `./sync_task.sh` to manually do a real bisync, and inspect the `./app/logs/sync.log` log output.
6. Run `sudo ./build.sh --stop` and then customize the `docker-compose.yml` file to match your needs.
7. Run `sudo docker-compose up -d` to start the finished container.

### Portainer/Komodo app setup (follow the instructions above first)

1. Import your customized `.env` file variables.
2. Copy the contents of the `docker-compose.yml` file into your container setup.
3. Remove the `build: ...` section entirely.
4. Ensure the `image: ...` ref matches your `IMAGENAME` tag from the `.env` file.
5. Manually run `sudo ./build.sh -b` command when you want to rebuild/update the container.
6. Redeploy the application and enjoy!
