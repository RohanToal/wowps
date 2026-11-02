#!/usr/bin/env bash
# Restore the databases from a backup in ./backups. Everything since that
# backup (new characters, progress...) is lost. Files in config/ are NOT
# changed; the backup's copy is in backups/<name>/config.tar.gz if you need it.
#
# Usage: ./restore.sh <backup-name> [--yes]
#        ./restore.sh                  (lists the backups)
source "$(dirname "$0")/scripts/lib.sh"

name=""
assume_yes=0
for arg in "$@"; do
    case "$arg" in
        -h | --help)
            sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -y | --yes) assume_yes=1 ;;
        *) name="${arg%/}" && name="${name#backups/}" ;;
    esac
done

require_docker
require_env

if [ -z "$name" ]; then
    echo "Available backups (newest last):"
    found=0
    for dir in "$ROOT_DIR"/backups/*/; do
        [ -d "$dir" ] || continue
        case "$dir" in *.partial/) continue ;; esac
        basename "$dir"
        found=1
    done
    [ "$found" -eq 1 ] || echo "  (none)"
    echo
    echo "Usage: ./restore.sh <backup-name>"
    exit 1
fi
[ -d "$ROOT_DIR/backups/$name" ] || die "Backup 'backups/$name' not found. Run ./restore.sh to list backups."

if [ "$assume_yes" -ne 1 ]; then
    warn "This replaces ALL accounts, characters and bots with the backup '$name'."
    printf 'Type "yes" to continue: '
    read -r answer
    [ "$answer" = "yes" ] || die "Cancelled."
fi

was_running=0
container_running ac-worldserver && was_running=1

info "Stopping the game servers..."
docker compose stop ac-worldserver ac-authserver >/dev/null 2>&1 || true

info "Restoring backups/$name ..."
db_tools restore "$name"
ok "Database restored."

if [ "$was_running" -eq 1 ]; then
    "$ROOT_DIR/start.sh"
else
    docker compose down >/dev/null 2>&1 || true
    echo "Start the server with ./start.sh"
fi
