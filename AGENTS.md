# AGENTS.md — universal-odoo-backup

## Overview
Simple Bash backup utilities for Odoo (v11+) databases. No build/test/lint commands.

## Scripts

- `odoo-backup.sh` — Local backup using Odoo shell. Run as the Odoo system user.
- `run-remote-backup.sh` — Remote backup via SSH + rsync. Copies script to remote, runs it, pulls backup.

## Run commands

```bash
./odoo-backup.sh <db_name> [<backup_dir>]
./odoo-backup.sh --help

./run-remote-backup.sh user@host [<db_name>] [<local_dir>]
./run-remote-backup.sh --help
```

## Important quirks

- `odoo-backup.sh` must run as the same OS user running Odoo (needs read access to filestore and Odoo Python environment)
- Uses `odoo-bin shell` via stdin—no HTTP needed
- `run-remote-backup.sh` extracts db name from hostname (e.g., `admin@prod1.binex.cloud` → `prod1`)
- Remote execution uses `sudo -u odoo` to run the script as Odoo user

## Environment variables

- `ODOO_CONF` — path to odoo.conf (default: `/etc/odoo/odoo.conf`)
- `BACKUP_DIR` — output directory
- `BACKUP_FORMAT` — `zip` (with filestore) or `dump` (pg only)
- `REMOTE_CONF` — remote odoo.conf path
- `REMOTE_BACKUP_DIR` — remote backup directory (default: `/opt/odoo-server/backups`)