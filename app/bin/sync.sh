#!/usr/bin/env bash
set -euo pipefail
#
# Unified rclone sync script - combines first-run and regular sync functionality
#

# Default configuration file path
CONFIG_FILE="${CONFIG_FILE:-/app/sync.conf}"

# Load configuration from file if it exists
load_configuration() {
  if [[ -f "$CONFIG_FILE" ]]; then # shellcheck disable=SC1090
    # Source the configuration file
    source "$CONFIG_FILE"
  else
    echo "Configuration file not found: $CONFIG_FILE" >&2
    echo "Using default values or environment variables." >&2
  fi
}

# Validate critical configuration variables
validate_configuration() {
  local missing_vars=()
  local critical_vars=(
    "BASE_DIR"
    "CONFIG_DIR"
    "RCLONE_FILE"
    "LOG_DIR"
    "FILTER_FILE"
    "SRC_DIR"
    "TGT_DIR"
    "LOCK_DIR"
    "INITIAL_LOCK"
    "INITIAL_DRY_LOCK"
    "BISYNC_LOCK"
    "INITIAL_SYNC_LOG"
    "LOG_FILE"
    "LOG_MAX_SIZE"
    "LOG_MAX_BACKUPS"
  )

  for var_name in "${critical_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
      missing_vars+=("$var_name")
    fi
  done

  if [[ ${#missing_vars[@]} -gt 0 ]]; then
    echo "ERROR: Missing required configuration variables:" >&2
    for var in "${missing_vars[@]}"; do
      echo "  - $var" >&2
    done
    return 1
  fi

  return 0
}

# Load configuration
load_configuration

# Apply environment variable overrides with defaults
BASE_DIR="${BASE_DIR:-/app}"
CONFIG_DIR="${CONFIG_DIR:-${BASE_DIR}/rclone}"
RCLONE_FILE="${RCLONE_FILE:-${CONFIG_DIR}/rclone.conf}"
LOG_DIR="${LOG_DIR:-/app/logs}"
FILTER_FILE="${FILTER_FILE:-${CONFIG_DIR}/filters}"
SRC_DIR="${SRC_DIR:-/synctarget}"
TGT_DIR="${TGT_DIR:-gdrive:/Backups}"
LOCK_DIR="${LOCK_DIR:-${BASE_DIR}/locks}"
INITIAL_LOCK="${INITIAL_LOCK:-${LOCK_DIR}/.initial_sync_lock}"
INITIAL_DRY_LOCK="${INITIAL_DRY_LOCK:-${LOCK_DIR}/.initial_drysync_lock}"
BISYNC_LOCK="${BISYNC_LOCK:-${LOCK_DIR}/.sync_lock}"
INITIAL_SYNC_LOG="${INITIAL_SYNC_LOG:-${LOG_DIR}/initial-sync.log}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/sync.log}"
LOG_MAX_SIZE="${LOG_MAX_SIZE:-1048576}"
LOG_MAX_BACKUPS="${LOG_MAX_BACKUPS:-3}"

# Validate configuration after applying defaults
if ! validate_configuration; then
  exit 1
fi

# Global operation flags
FIRST_RUN=false
DRY_RUN=false
FORCE=false
INITIAL_DRY_RUN_COMPLETED=false

# Log rotation configuration
LOG_MAX_SIZE="${LOG_MAX_SIZE:-1048576}" # 1MiB default
LOG_MAX_BACKUPS="${LOG_MAX_BACKUPS:-3}" # Keep 3 backups by default

# Display usage information
show_usage() {
  local script_name
  script_name="$(basename "$0")"

  cat <<EOF
Usage: ${script_name} [--first-run] [--safe|--dry-run] [--force]

Options:
  --first-run    Perform initial sync (NOTE: requires dry-run first, then re-run for initial sync)
  --safe, --dry-run  Perform dry run (no changes made)
  --force        Force sync (overwrite conflicts)
  --help         Show this help message
EOF
}

# Parse command line arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --first-run)
      FIRST_RUN=true
      shift
      ;;
    --safe | --dry-run)
      DRY_RUN=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --help)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
    esac
  done
}

# Validate first-run requirements
validate_first_run() {
  # Check if both initial dry-run and initial sync have been completed
  if [[ -f "$INITIAL_DRY_LOCK" && -f "$INITIAL_LOCK" ]]; then
    echo "Both initial dry-run and initial sync already completed. Proceeding with actual sync..."
    return 0
  fi

  # Check if initial dry-run has been completed
  if [[ -f "$INITIAL_DRY_LOCK" ]]; then
    echo "Initial dry-run already completed. Proceeding with actual sync..."
    return 0
  fi

  # First time running --first-run, force dry-run mode unless explicitly requested
  if [[ "$DRY_RUN" != true ]]; then
    echo "First-run requires initial dry-run. Forcing --dry-run mode."
    echo "After reviewing the dry-run output, re-run with --first-run to execute the actual sync."
    DRY_RUN=true
    INITIAL_DRY_RUN_COMPLETED=true
  fi

  # Remove test file if it exists (fresh start)
  rm -f "$INITIAL_LOCK"
}

# Validate regular sync requirements
validate_regular_sync() {
  # Check if first-run has been completed
  if [[ ! -f "$INITIAL_LOCK" ]]; then
    echo "First run not completed. Use --first-run flag or ensure $INITIAL_LOCK exists"
    exit 1
  fi

  # Check if bisync lock file exists (required for normal operations)
  if [[ ! -f "$BISYNC_LOCK" ]]; then
    echo "Bisync lock file not found. Normal sync operations require a completed first-run."
    echo "Please run with --first-run flag to initialize the sync."
    exit 1
  fi
}

# Create or update bisync lock file
create_bisync_lock() {
  # Create lock file with timestamp and sync information
  cat >"$BISYNC_LOCK" <<EOF
# Bisync Lock File - Created by rcloner-redux sync script
# This file ensures that normal bisync operations only run after successful first-run
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SOURCE_PATH=$SRC_DIR
DEST_PATH=gdrive:/
SYNC_TYPE=bisync
EOF

  echo "Bisync lock file created/updated at: $BISYNC_LOCK"
}

# Get the appropriate log file based on operation type
get_log_file() {
  if [[ "$FIRST_RUN" == true ]]; then
    echo "$INITIAL_SYNC_LOG"
  else
    echo "$LOG_FILE"
  fi
}

# Get sync operation description
get_sync_description() {
  local description=""

  if [[ "$FIRST_RUN" == true ]]; then
    if [[ "$INITIAL_DRY_RUN_COMPLETED" == true ]]; then
      description="initial dry-run"
    else
      description="first-run"
    fi
  elif [[ "$DRY_RUN" == true ]]; then
    description="dry-run"
  elif [[ "$FORCE" == true ]]; then
    description="forced"
  else
    description="normal"
  fi

  echo "$description"
}

# Detect and validate rclone binary
detect_rclone() {
  # Check if RCLONE_BIN is already set via environment variable
  if [[ -n "${RCLONE_BIN:-}" ]]; then
    # Validate the provided path
    if [[ -x "$RCLONE_BIN" ]]; then
      echo "$RCLONE_BIN"
      return 0
    else
      echo "ERROR: RCLONE_BIN environment variable points to non-executable file: $RCLONE_BIN" >&2
      return 1
    fi
  fi

  # Try to find rclone in PATH using command -v (more reliable than which)
  local rclone_path
  rclone_path="$(command -v rclone 2>/dev/null || true)"

  if [[ -n "$rclone_path" && -x "$rclone_path" ]]; then
    echo "$rclone_path"
    return 0
  fi

  # If not found, provide helpful error message
  echo "ERROR: 'rclone' not found in PATH or RCLONE_BIN env var!" >&2
  return 1
}

# Build rclone bisync command
build_rclone_command() {
  local rclone_bin="$1"
  local cmd=("$rclone_bin" --config "$RCLONE_FILE" bisync)

  # Add operation mode flags
  if [[ "$DRY_RUN" == true ]]; then
    cmd+=("--dry-run")
  elif [[ "$FORCE" == true ]]; then
    cmd+=("--force")
  fi

  # Add common bisync options
  cmd+=(
    "--config" "$RCLONE_FILE"
    "--filter-from" "$FILTER_FILE"
    "--compare" "size,modtime,checksum"
    "--resilient"
    "--recover"
    "--drive-skip-gdocs"
    "--fix-case"
    "--timeout 10s"
    "--drive-acknowledge-abuse"
    "-Mv"
  )

  # Add resync flag for first-run
  if [[ "$FIRST_RUN" == true ]]; then
    cmd+=("--resync")
  fi

  # Add source and destination paths
  cmd+=("$SRC_DIR" "$TGT_DIR")

  echo "${cmd[@]}"
}

# Initialize logging
initialize_logging() {
  local log_file
  log_file="$(get_log_file)"

  # Ensure log directory exists
  mkdir -p "$LOG_DIR"
  touch "$log_file"

  # Add timestamp to log
  local description
  description="$(get_sync_description)"
  echo "Starting ${description} sync at $(date)" >>"$log_file"
  echo "Running ${description} sync..."
}

# Execute the sync command
execute_sync() {
  local rclone_bin="$1"
  local log_file
  log_file="$(get_log_file)"

  # Build and execute the command
  local cmd
  cmd="$(build_rclone_command "$rclone_bin")"

  if ! eval "$cmd" 2>&1 | tee -a "$log_file"; then
    echo "Sync failed! Check logs at: $log_file"
    return 1
  fi

  return 0
}

# Handle post-sync completion
handle_completion() {
  local log_file
  log_file="$(get_log_file)"

  if [[ "$FIRST_RUN" == true ]]; then
    if [[ "$INITIAL_DRY_RUN_COMPLETED" == true ]]; then
      # Mark initial dry-run as completed
      touch "$INITIAL_DRY_LOCK"
      echo "Initial dry-run completed successfully. Review logs at: $log_file"
      echo "To execute the actual sync, run: $0 --first-run"
    else
      # Mark first-run as completed
      touch "$INITIAL_LOCK"
      # Create/update bisync lock file
      create_bisync_lock
      echo "First run completed successfully. Logs: $log_file"
    fi
  else
    echo "Sync completed successfully. Logs: $log_file"
  fi
}

# Rotate log files when they exceed size threshold
# Usage: rotate_logs "/path/to/logfile.log" [max_size_bytes] [max_backups]
rotate_logs() {
  local log_file="$1"
  local max_size="${2:-4194304}" # Default: 4MiB (4 * 1024 * 1024 bytes)
  local max_backups="${3:-5}"    # Default: keep 5 backups

  # Check if log file exists and get its size
  if [[ ! -f "$log_file" ]]; then
    return 0
  fi

  local current_size
  current_size=$(stat -c%s "$log_file" 2>/dev/null || echo "0")

  # If file size is below threshold, no rotation needed
  if ((current_size < max_size)); then
    return 0
  fi

  # Find the highest existing backup number
  local highest_num=0
  local backup_files
  # Use nullglob to handle no matches, redirect stderr to avoid errors
  shopt -s nullglob
  backup_files=("$log_file".*)
  shopt -u nullglob

  for backup in "${backup_files[@]}"; do
    # Extract number from filename pattern: logfile.log.1, logfile.log.2, etc.
    if [[ "$backup" =~ \.([0-9]+)$ ]]; then
      local num="${BASH_REMATCH[1]}"
      if ((num > highest_num)); then
        highest_num="$num"
      fi
    fi
  done

  # Shift existing backups (start from highest to avoid overwrites)
  local num="$highest_num"
  while ((num >= 1)); do
    local current_backup="${log_file}.${num}"
    local next_backup="${log_file}.$((num + 1))"

    if ((num == max_backups)); then
      # Remove oldest backup if we've reached max_backups
      rm -f "$current_backup"
    elif [[ -f "$current_backup" ]]; then
      # Shift backup to next number
      mv "$current_backup" "$next_backup"
    fi

    ((num--))
  done

  # Create new .1 backup from current log
  mv "$log_file" "${log_file}.1"

  # Create fresh empty log file
  touch "$log_file"

  echo "Rotated logs: $log_file -> ${log_file}.1 (size: ${current_size} bytes)"
}

# ============================================
# MAIN EXECUTION
# ============================================

main() {
  # Detect rclone binary first
  local rclone_bin
  if ! rclone_bin="$(detect_rclone)"; then
    exit 1
  fi

  # Parse command line arguments
  parse_arguments "$@"

  # Validate requirements based on operation mode
  if [[ "$FIRST_RUN" == true ]]; then
    validate_first_run
  else
    validate_regular_sync
  fi

  # Rotate logs before starting new operation
  local log_file
  log_file="$(get_log_file)"
  rotate_logs "$log_file" "$LOG_MAX_SIZE" "$LOG_MAX_BACKUPS"

  # Initialize logging
  initialize_logging

  # Execute the sync
  if ! execute_sync "$rclone_bin"; then
    exit 1
  fi

  # Handle completion
  handle_completion
}

# Run main function with all arguments
main "$@"
