# odoo-shell-backup

Odoo backup tools — compatible v11+ via odoo-bin shell.

## Scripts

### `odoo-backup-local.sh` — Local backup

Run on the same host as Odoo (as the odoo user):

```bash
./odoo-backup-local.sh <db_name> [<backup_dir>]
./odoo-backup-local.sh --help
```

### `odoo-backup-remote.sh` — Remote backup via SSH + rsync

Run from your local machine to back up a remote Odoo instance:

```bash
./odoo-backup-remote.sh user@host [<db_name>] [<local_dir>]
./odoo-backup-remote.sh admin@prod1.binex.cloud
./odoo-backup-remote.sh admin@prod1.binex.cloud mydb ./backups/
./odoo-backup-remote.sh -d admin@host mydb  # dry run
```

## Requirements

- Bash 4.2+
- SSH access to remote host
- rsync installed locally
- Remote host: sudo access to odoo user, odoo-bin available