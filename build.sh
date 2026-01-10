#!/usr/bin/env bash

ENV_FILE="${ENV_FILE:-.env}"
# read vars from .env
if [ -r "${ENV_FILE}" ]; then # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

# Default values for flags
BUILD_ONLY=false
RUN_CONTAINER=false
OPEN_SHELL=false

# Help message
show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  -b, --build    Build the Docker image (default)"
  echo "  -r, --run      Run the container after building"
  echo "  -s, --shell    Open a shell in the running container"
  echo "  -h, --help     Show this help message"
}

# Function to parse command-line arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -b | --build)
      BUILD_ONLY=true
      shift
      ;;
    -r | --run)
      RUN_CONTAINER=true
      shift
      ;;
    -s | --shell)
      OPEN_SHELL=true
      shift
      ;;
    --stop)
      STOP_CONTAINER=true
      shift
      ;;
    -h | --help)
      show_help
      exit 0
      ;;
    *)
      echo "Invalid option: $1" >&2
      show_help
      exit 1
      ;;
    esac
  done
}

build_container() {
  # Build the Docker image
  echo "Building container..."
  if docker build \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    --build-arg TZ="${TZ}" \
    -t "${IMAGENAME}:latest" .; then
    return 0 # success
  else
    echo "Error: Failed to build container" >&2
    return 1 # failure
  fi
}

run_container() {
  echo "Running container..."

  stop_container
  FOLDERS=(
    "${APPROOT}/app/logs"
    "${APPROOT}/app/locks"
    "${APPROOT}/app/cache"
  )
  mkdir -p "${FOLDERS[@]}"

  if docker run -d --rm --name "${IMAGENAME}" \
    -v "${APPROOT}"/logs:/app/logs \
    -v "${APPROOT}"/locks:/app/locks \
    -v "${APPROOT}"/cache:/app/.cache/rclone \
    -v "${APPROOT}"/rclone:/app/rclone \
    -v "${APPROOT}"/sync.conf:/app/sync.conf \
    -v "${SYNCTARGET}":/synctarget \
    "${IMAGENAME}:latest"; then
    return 0 # success
  else
    echo "Error: Failed to run container" >&2
    return 1 # failure
  fi
}

stop_container() {
  if docker stop "${IMAGENAME}"; then
    echo "Container '${IMAGENAME}' stopped successfully"
    return 0
  else
    return 1
  fi
}

call_shell() {
  echo "Opening shell..."
  if docker exec -it "${IMAGENAME}" /bin/bash; then
    return 0 # success
  else
    return 1 # failure
  fi
}

container_exists() {
  if docker ps -a --format '{{.Names}}' | grep -q "^${IMAGENAME}$"; then
    return 0
  else
    return 1
  fi
}

# Main logic
main() {
  if [ "$STOP_CONTAINER" = true ]; then
    stop_container
    return $?
  fi

  if [ "$BUILD_ONLY" = true ]; then
    build_container
    return $?
  fi

  if [ "$RUN_CONTAINER" = true ] || [ "$OPEN_SHELL" = true ]; then
    if ! container_exists; then
      build_container || return $?
      [ "$RUN_CONTAINER" = true ] && run_container || return $?
    else
      echo "Container already exists, skipping build..."
      # Only run container if explicitly requested and it's not already running
      if [ "$RUN_CONTAINER" = true ]; then
        if ! container_exists; then
          run_container || return $?
        fi
      fi
    fi

    [ "$OPEN_SHELL" = true ] && call_shell || return $?
    return 0
  fi

  # Default: build only
  build_container
  return $?
}

parse_arguments "$@"
main
exit $?
