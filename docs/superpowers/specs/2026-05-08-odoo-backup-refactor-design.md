# Design: odoo-backup-local.sh Refactor

**Date:** 2026-05-08  
**Status:** Approved

## Goal
Improve `odoo-backup-local.sh` for cleanliness, maintainability, and clarity without adding external dependencies or changing the core backup mechanism.

## Approach
Refactor into named, single-responsibility functions (Option B). `main()` orchestrates them top-to-bottom. Single file.

## Function Layout
- `usage()` — print full help, exit 0
- `parse_args()` — handle -h/--help, positional args, unknown flags
- `resolve_odoo_bin()` — locate odoo-bin or odoo binary
- `parse_odoo_conf()` — extract db_name from odoo.conf (POSIX grep/awk only)
- `validate_env()` — early-exit guards
- `run_backup()` — write python tmpfile, exec odoo shell, confirm output
- `main()` — orchestrates all of the above

## Help Text
Printed by `usage()` and triggered by `-h`/`--help`. Includes user requirement notice: must be run as the same OS user as the Odoo service.

## `parse_odoo_conf()`
Called only when DB_NAME was not supplied. Uses grep/awk on ODOO_CONF. Fails with clear error if multiple db names found (comma in value).

## `validate_env()` Guards (in order)
1. ODOO_CONF exists and is readable
2. BACKUP_DIR can be created and is writable
3. DB_NAME contains no commas

## `run_backup()`
1. Write Python to mktemp file
2. trap to remove on exit
3. exec odoo shell < tmpfile
4. confirm output file exists from bash, print size

## Non-Goals
- No remote/cloud storage
- No backup rotation
- No scheduling
- No new external dependencies
