#!/usr/bin/env bash
# run-remote-backup.sh — Remote Odoo backup via SSH + rsync
set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
REMOTE_CONF="${REMOTE_CONF:-/etc/odoo/odoo.conf}"
BACKUP_FORMAT="${BACKUP_FORMAT:-zip}"
LOCAL_DIR="$(pwd)"
REMOTE_BACKUP_DIR="${REMOTE_BACKUP_DIR:-/opt/odoo-server/backups}"
DRY_RUN=false
VERBOSE=false
SSH_USER_HOST=""
DB_NAME=""

# ─── usage ───────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <user@host> [<db_name>] [<local_backup_dir>]

Backup an Odoo database from a remote host via SSH + rsync.

Arguments:
  <user@host>         Remote host to connect to
  [<db_name>]         Database name (default: extracted from hostname)
  [<local_backup_dir>]  Local directory for backup (default: current directory)

Options:
  -h, --help          Show this help and exit
  -c, --conf PATH     Remote odoo.conf path (default: /etc/odoo/odoo.conf)
  -r, --remote-dir    Remote backup directory (default: /opt/odoo-server/backups)
  -f, --format FMT    Backup format: zip|dump (default: zip)
  -d, --dry-run       Show what would happen without executing
  -v, --verbose       Show debug output from SSH and rsync

Examples:
  $(basename "$0") admin@prod1.binex.cloud
  $(basename "$0") admin@prod1.binex.cloud ./backups/
  $(basename "$0") admin@prod1.binex.cloud mydb ./backups/
  $(basename "$0") -f dump admin@host mydb
  $(basename "$0") -d admin@host mydb  # dry run
EOF
}

# ─── parse_args ──────────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -c|--conf)
        REMOTE_CONF="$2"
        shift 2
        ;;
      -r|--remote-dir)
        REMOTE_BACKUP_DIR="$2"
        shift 2
        ;;
      -f|--format)
        BACKUP_FORMAT="$2"
        shift 2
        ;;
      -d|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -v|--verbose)
        VERBOSE=true
        shift
        ;;
      -*)
        echo "[ERROR] Unknown option: $1" >&2
        echo "Run '$(basename "$0") --help' for usage." >&2
        exit 1
        ;;
      *)
        if [ -z "$SSH_USER_HOST" ]; then
          SSH_USER_HOST="$1"
          shift
        elif [ -z "$DB_NAME" ]; then
          # If second arg contains '/', it's a local directory path, not db_name
          if [[ "$1" == */* ]]; then
            LOCAL_DIR="$1"
          else
            DB_NAME="$1"
          fi
          shift
        elif [ "$LOCAL_DIR" = "$(pwd)" ]; then
          LOCAL_DIR="$1"
          shift
        else
          echo "[ERROR] Unexpected argument: $1" >&2
          echo "Run '$(basename "$0") --help' for usage." >&2
          exit 1
        fi
        ;;
    esac
  done
}

# ─── extract_db_from_hostname ────────────────────────────────────────────────
extract_db_from_hostname() {
  local host_part="${SSH_USER_HOST#*@}"

  if [[ "$host_part" =~ ^([a-zA-Z0-9_-]+)\.binhex\.cloud$ ]]; then
    DB_NAME="${BASH_REMATCH[1]}"
  else
    DB_NAME="$host_part"
  fi
}

# ─── ssh_cmd ─────────────────────────────────────────────────────────────────
ssh_cmd() {
  if $VERBOSE; then
    ssh "$SSH_USER_HOST" "$@"
  else
    ssh -q "$SSH_USER_HOST" "$@"
  fi
}

# ─── get_remote_filestore_size ───────────────────────────────────────────────
get_remote_filestore_size() {
  local data_dir
  data_dir=$(ssh_cmd "grep -E '^\s*data_dir\s*=' $REMOTE_CONF 2>/dev/null | awk -F'=' '{print \$2}' | tr -d ' '" || true)

  if [ -z "$data_dir" ]; then
    # Use getent to get odoo user's home directory reliably
    data_dir=$(ssh_cmd "getent passwd odoo | cut -d: -f6")/.local/share/Odoo
  fi

  local fs_path="${data_dir}/filestore/${DB_NAME}"

  local size_mb
  size_mb=$(ssh_cmd "sudo -u odoo du -sm $fs_path 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo "0")

  echo "$size_mb"
}

# ─── check_remote_space ──────────────────────────────────────────────────────
check_remote_space() {
  local fs_size_mb="$1"

  local estimated_mb
  if [ "$fs_size_mb" -gt 0 ] 2>/dev/null; then
    estimated_mb=$(( fs_size_mb * 7 / 10 ))
  else
    estimated_mb=5120
  fi

  local available_kb
  available_kb=$(ssh_cmd "df / | awk 'NR==2 {print \$4}'" 2>/dev/null || echo "0")
  local available_gb=$(( available_kb / 1024 / 1024 ))
  local available_mb=$(( available_kb / 1024 ))

  local threshold_mb=$(( estimated_mb * 3 / 2 ))

  echo "[INFO] Estimated backup size: $(( estimated_mb / 1024 )) GB ($(( estimated_mb % 1024 )) MB)"
  echo "[INFO] Available space: ${available_gb} GB"

  if [ "$available_mb" -lt "$threshold_mb" ]; then
    echo "[WARN] Low disk space. Estimated: $(( estimated_mb / 1024 )) GB, Available: ${available_gb} GB"
    read -rp "Continue? [y/N] " response
    if [[ "$response" != [yY]* ]]; then
      echo "[INFO] Aborted by user."
      exit 0
    fi
  fi
}

# ─── run_remote_backup ───────────────────────────────────────────────────────
run_remote_backup() {
  echo "[INFO] Starting remote backup..." >&2
  echo "[INFO] Host     : $SSH_USER_HOST" >&2
  echo "[INFO] Database : $DB_NAME" >&2
  echo "[INFO] Format   : $BACKUP_FORMAT" >&2
  echo "[INFO] Config   : $REMOTE_CONF" >&2
  echo "" >&2

  local output
  local script_file="/tmp/odoo-backup-$$.sh"
  
  # Copy script to remote temp file and execute it to avoid stdin complications
  # This prevents issues with interactive prompts or script reading stdin
  scp -q "$(dirname "$0")/odoo-backup.sh" "$SSH_USER_HOST:$script_file" || {
    echo "[ERROR] Failed to copy backup script to remote host." >&2
    return 1
  }
  
  output=$(ssh_cmd "sudo -u odoo env ODOO_CONF='$REMOTE_CONF' BACKUP_FORMAT='$BACKUP_FORMAT' BACKUP_DIR='$REMOTE_BACKUP_DIR' bash $script_file $DB_NAME" 2>&1)
  
  # Clean up remote temp file
  ssh_cmd "rm -f $script_file" 2>/dev/null || true

  echo "$output" | while IFS= read -r line; do
    if [[ "$line" == *"[INFO]"* ]] || [[ "$line" == *"[PY]"* ]]; then
      echo "$line" >&2
    elif [[ "$line" == *"[ERROR]"* ]]; then
      echo "$line" >&2
    fi
  done

  local backup_file
  backup_file=$(echo "$output" | grep '\[INFO\] Done:' | tail -1 | sed 's/.*Done: \([^ ]*\).*/\1/')

  if [ -z "$backup_file" ]; then
    echo "[ERROR] Could not determine remote backup file path." >&2
    echo "[ERROR] Remote output was:" >&2
    echo "$output" >&2
    exit 1
  fi

  # Return backup file path via stdout ONLY - all logging goes to stderr
  echo "$backup_file"
}

# ─── rsync_backup ─────────────────────────────────────────────────────────────
rsync_backup() {
  local remote_file="$1"

  echo "[INFO] Pulling backup via rsync..."
  mkdir -p "$LOCAL_DIR"

  if $VERBOSE; then
    rsync -av --progress "$SSH_USER_HOST:$remote_file" "$LOCAL_DIR/"
  else
    rsync -a --progress "$SSH_USER_HOST:$remote_file" "$LOCAL_DIR/"
  fi

  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "[ERROR] rsync failed with exit code $exit_code" >&2
    echo "[INFO] Remote backup preserved at: $remote_file" >&2
    exit 1
  fi

  echo "[INFO] Backup pulled to: $LOCAL_DIR/"
}

# ─── cleanup_remote ──────────────────────────────────────────────────────────
cleanup_remote() {
  local remote_file="$1"

  echo "[INFO] Cleaning up remote backup..."
  if ssh_cmd "rm -f $remote_file" 2>/dev/null; then
    echo "[INFO] Remote cleanup complete."
  else
    echo "[WARN] Failed to clean up remote file: $remote_file" >&2
  fi
}

# ─── main ────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"

  if [ -z "${SSH_USER_HOST:-}" ]; then
    echo "[ERROR] Remote host required. Run '$(basename "$0") --help' for usage." >&2
    exit 1
  fi

  if [ -z "$DB_NAME" ]; then
    extract_db_from_hostname
    echo "[INFO] Using database name from hostname: $DB_NAME"
  fi

  if $DRY_RUN; then
    echo "[DRY RUN] Would connect to: $SSH_USER_HOST"
    echo "[DRY RUN] Database: $DB_NAME"
    echo "[DRY RUN] Config: $REMOTE_CONF"
    echo "[DRY RUN] Format: $BACKUP_FORMAT"
    echo "[DRY RUN] Local dir: $LOCAL_DIR"
    exit 0
  fi

  echo "[INFO] Estimating backup size..."
  local fs_size_mb
  fs_size_mb=$(get_remote_filestore_size)
  if [ "$fs_size_mb" -gt 0 ] 2>/dev/null; then
    echo "[INFO] Filestore size: $(( fs_size_mb / 1024 )) GB ($(( fs_size_mb % 1024 )) MB)"
  else
    echo "[WARN] Could not determine filestore size, using default estimate."
  fi

  check_remote_space "$fs_size_mb"

  local backup_file
  backup_file=$(run_remote_backup)

  rsync_backup "$backup_file"
  cleanup_remote "$backup_file"

  echo ""
  echo "[INFO] All done. Backup saved to: $LOCAL_DIR/"
}

main "$@"