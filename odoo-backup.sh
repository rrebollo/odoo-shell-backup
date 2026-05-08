#!/usr/bin/env bash
# odoo-backup.sh — Odoo backup via odoo-bin shell (compatible v11+)
# Run as the same OS user that owns the Odoo service.
set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
ODOO_CONF="${ODOO_CONF:-/etc/odoo/odoo.conf}"
BACKUP_DIR="${BACKUP_DIR:-$(pwd)}"
BACKUP_FORMAT="${BACKUP_FORMAT:-zip}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
DB_NAME=""
ODOO_BIN=""

# ─── usage ───────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [<db_name> [<backup_dir>]]

Backup an Odoo database using odoo-bin shell (no external dependencies).

  <db_name>     Database to back up. If omitted, reads 'db_name' from
                ODOO_CONF (fails if conf lists multiple databases).
  <backup_dir>  Destination directory. Default: current working directory,
                or BACKUP_DIR env var.

Options:
  -h, --help    Show this help and exit.

Environment variables:
  ODOO_CONF       Path to odoo.conf  (default: /etc/odoo/odoo.conf)
  BACKUP_DIR      Output directory   (default: current directory)
  BACKUP_FORMAT   zip (with filestore) | dump (pg only)  (default: zip)

Requirements:
  - Must be run as the same OS user that runs the Odoo service
    (needs read access to the filestore and the Odoo Python environment).
  - No external tools required beyond Odoo itself.
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
      -*)
        echo "[ERROR] Unknown option: $1" >&2
        echo "Run '$(basename "$0") --help' for usage." >&2
        exit 1
        ;;
      *)
        if   [ -z "$DB_NAME" ];    then DB_NAME="$1"
        elif [ "$BACKUP_DIR" = "$(pwd)" ]; then BACKUP_DIR="$1"
        else
          echo "[ERROR] Unexpected argument: $1" >&2
          echo "Run '$(basename "$0") --help' for usage." >&2
          exit 1
        fi
        ;;
    esac
    shift
  done
}

# ─── resolve_odoo_bin ─────────────────────────────────────────────────────────
resolve_odoo_bin() {
  if   command -v odoo-bin &>/dev/null; then ODOO_BIN="odoo-bin"
  elif command -v odoo     &>/dev/null; then ODOO_BIN="odoo"
  elif [ -f ./odoo-bin ];               then ODOO_BIN="./odoo-bin"
  elif [ -f ./odoo ];                   then ODOO_BIN="./odoo"
  else
    echo "[ERROR] No odoo / odoo-bin binary found. Set PATH or run from Odoo root." >&2
    exit 1
  fi
}

# ─── parse_odoo_conf ──────────────────────────────────────────────────────────
parse_odoo_conf() {
  [ -n "$DB_NAME" ] && return 0

  local raw
  raw=$(grep -E '^\s*db_name\s*=' "$ODOO_CONF" | awk -F'=' '{print $2}' | tr -d ' ')

  if [ -z "$raw" ]; then
    echo "[ERROR] 'db_name' not found in ${ODOO_CONF}." >&2
    echo "        Pass <db_name> as an argument or set it in the config." >&2
    exit 1
  fi

  if [[ "$raw" == *,* ]]; then
    echo "[ERROR] Multiple databases found in ${ODOO_CONF}: ${raw}" >&2
    echo "        Pass a single <db_name> as an argument." >&2
    exit 1
  fi

  DB_NAME="$raw"
}

# ─── validate_env ────────────────────────────────────────────────────────────
validate_env() {
  if [ ! -f "$ODOO_CONF" ] || [ ! -r "$ODOO_CONF" ]; then
    echo "[ERROR] Odoo config not found or not readable: ${ODOO_CONF}" >&2
    echo "        Set ODOO_CONF or ensure the file exists." >&2
    exit 1
  fi

  if ! mkdir -p "$BACKUP_DIR" 2>/dev/null || [ ! -w "$BACKUP_DIR" ]; then
    echo "[ERROR] Backup directory is not writable: ${BACKUP_DIR}" >&2
    exit 1
  fi

  if [[ "$DB_NAME" == *,* ]]; then
    echo "[ERROR] DB_NAME contains multiple values: ${DB_NAME}" >&2
    echo "        Pass a single database name." >&2
    exit 1
  fi
}

# ─── run_backup ──────────────────────────────────────────────────────────────
run_backup() {
  local backup_file="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.${BACKUP_FORMAT}"

  echo "[INFO] Binary   : ${ODOO_BIN}"
  echo "[INFO] Config   : ${ODOO_CONF}"
  echo "[INFO] Database : ${DB_NAME}"
  echo "[INFO] Format   : ${BACKUP_FORMAT}"
  echo "[INFO] Output   : ${backup_file}"
  echo "[INFO] Launching odoo shell ..."

  local pyfile
  pyfile="$(mktemp /tmp/odoo_backup_XXXXXX.py)"
  trap 'rm -f "$pyfile"' EXIT

  cat > "$pyfile" <<PYEOF
import sys, os

backup_file   = ${backup_file@Q}
backup_format = ${BACKUP_FORMAT@Q}
db_name       = ${DB_NAME@Q}

print(f"[PY]  Importing odoo.service.db ...")
import odoo.service.db as db_svc

print(f"[PY]  Starting backup: db={db_name}, format={backup_format}")
print(f"[PY]  Target file: {backup_file}")

try:
    with open(backup_file, "wb") as fh:
        db_svc.dump_db(db_name, fh, backup_format)
    size_mb = os.path.getsize(backup_file) / 1024 / 1024
    print(f"[PY]  Backup complete. Size: {size_mb:.2f} MB")
except Exception as exc:
    print(f"[PY]  ERROR: {exc}", file=sys.stderr)
    try:
        os.remove(backup_file)
    except OSError:
        pass
    sys.exit(1)

quit()
PYEOF

  "$ODOO_BIN" shell \
    --config="${ODOO_CONF}" \
    --db_host=False \
    --no-http \
    --database="${DB_NAME}" \
    < "$pyfile"

  if [ ! -f "$backup_file" ]; then
    echo "[ERROR] Backup file was not created: ${backup_file}" >&2
    exit 1
  fi

  local size_mb
  size_mb=$(du -m "$backup_file" | awk '{print $1}')
  echo "[INFO] Done: ${backup_file} (${size_mb} MB)"
}

# ─── main ────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"
  validate_env        # conf exists check runs before parse_odoo_conf needs it
  resolve_odoo_bin
  parse_odoo_conf
  validate_env        # re-run after db_name is populated to catch multi-db arg edge case
  run_backup
}

main "$@"
