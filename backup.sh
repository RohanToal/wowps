#!/usr/bin/env bash
# Back up all databases (accounts, characters, bots, world) plus config/ and
# .env into ./backups/<date>_<time>[_label]. Works whether the server is
# running or not. Old backups beyond BACKUP_KEEP (in .env) are deleted.
#
# Usage: ./backup.sh [label]      e.g. ./backup.sh before-raid
source "$(dirname "$0")/scripts/lib.sh"

case "${1:-}" in
    -h | --help)
        sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

require_docker
require_env
ensure_dirs

db_volume_exists || die "There is no database yet. Start the server once first."

db_was_running=0
container_running ac-database && db_was_running=1

info "Backing up..."
db_tools backup "${1:-}"

# Leave things the way they were: if the database was only started for the
# backup, stop it again.
if [ "$db_was_running" -eq 0 ]; then
    docker compose down >/dev/null 2>&1 || true
fi
ok "Backup complete."
