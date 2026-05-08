# universal-odoo-backup

Odoo backup tools — compatible v11+ via odoo-bin shell.

## Scripts

### `odoo-backup.sh` — Local backup

Run on the same host as Odoo (as the odoo user):

```bash
./odoo-backup.sh <db_name> [<backup_dir>]
./odoo-backup.sh --help
```

### `run-remote-backup.sh` — Remote backup via SSH + rsync

Run from your local machine to back up a remote Odoo instance:

```bash
./run-remote-backup.sh user@host [<db_name>] [<local_dir>]
./run-remote-backup.sh admin@prod1.binex.cloud
./run-remote-backup.sh admin@prod1.binex.cloud mydb ./backups/
./run-remote-backup.sh -d admin@host mydb  # dry run
```

## Requirements

- Bash 4.2+
- SSH access to remote host
- rsync installed locally
- Remote host: sudo access to odoo user, odoo-bin available