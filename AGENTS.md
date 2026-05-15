# AGENTS.md — odoo-shell-backup

## Overview
Simple Bash backup utilities for Odoo (v11+) databases. No build/test/lint commands.

## Scripts

- `odoo-backup-local` — Local backup using Odoo shell. Run as the Odoo system user.
- `odoo-backup-remote` — Remote backup via SSH + rsync. Copies script to remote, runs it, pulls backup.

## Run commands

```bash
./odoo-backup-local <db_name> [<backup_dir>]
./odoo-backup-local --help

./odoo-backup-remote user@host [<db_name>] [<local_dir>]
./odoo-backup-remote --help
```

## Important quirks

- `odoo-backup-local` must run as the same OS user running Odoo (needs read access to filestore and Odoo Python environment)
- Uses `odoo-bin shell` via stdin—no HTTP needed
- `odoo-backup-remote` extracts db name from hostname (e.g., `admin@prod1.binex.cloud` → `prod1`)
- Remote execution uses `sudo -u odoo` to run the script as Odoo user

## Environment variables

- `ODOO_CONF` — path to odoo.conf (default: `/etc/odoo/odoo.conf`)
- `BACKUP_DIR` — output directory
- `BACKUP_FORMAT` — `zip` (with filestore) or `dump` (pg only)
- `REMOTE_CONF` — remote odoo.conf path
- `REMOTE_BACKUP_DIR` — remote backup directory (default: `/opt/odoo-server/backups`)