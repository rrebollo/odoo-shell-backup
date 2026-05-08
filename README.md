# odoo-shell-backup

Odoo backup tools — compatible v11+ via odoo-bin shell.

## Installation

Download scripts directly from GitHub to `~/.local/bin`:

```bash
mkdir -p ~/.local/bin
curl -sL https://raw.githubusercontent.com/rrebollo/odoo-shell-backup/master/odoo-backup-local -o ~/.local/bin/odoo-backup-local
curl -sL https://raw.githubusercontent.com/rrebollo/odoo-shell-backup/master/odoo-backup-remote -o ~/.local/bin/odoo-backup-remote
chmod +x ~/.local/bin/odoo-backup-*
```

Add to PATH if needed:
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

Update later with:
```bash
# Same curl commands above - just re-run to get latest version
```

## Usage

Then run from anywhere:
```bash
odoo-backup-local <db_name> [<backup_dir>]
odoo-backup-remote user@host [<db_name>] [<local_dir>]
```

## Scripts

If running from this repo (instead of installing):

```bash
./odoo-backup-local <db_name> [<backup_dir>]
./odoo-backup-remote user@host [<db_name>] [<local_dir>]
```

Or install to PATH (see Installation above).

## Requirements

- Bash 4.2+
- SSH access to remote host
- rsync installed locally
- Remote host: sudo access to odoo user, odoo-bin available