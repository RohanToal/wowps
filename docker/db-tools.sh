#!/usr/bin/env bash
# Backup / restore helper. Runs inside the `ac-db-tools` container (MySQL
# image). The backup / restore scripts in the repo root call it, so the same
# logic works from bash and PowerShell.
#
#   db-tools.sh backup [label]   dump all databases + config into /backups/<timestamp>[_label]
#   db-tools.sh restore <name>   load the databases from /backups/<name>
#   db-tools.sh list             list the backups
set -euo pipefail

DB_HOST=ac-database
DATABASES=(acore_auth acore_characters acore_world acore_playerbots)
BACKUP_ROOT=/backups

mysql_cmd() {
    mysql -h "$DB_HOST" -uroot "$@"
}

db_exists() {
    [ -n "$(mysql_cmd -N -B -e "SHOW DATABASES LIKE '$1'")" ]
}

# Backup folder names start with a timestamp, e.g. 2026-11-02_15-04-05_before-update
list_backups() {
    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '[0-9][0-9][0-9][0-9]-*' ! -name '*.partial' \
        -printf '%f\n' | sort
}

cmd_backup() {
    local label="${1:-}"
    # Keep labels file-name safe.
    label="$(printf '%s' "$label" | tr -c 'A-Za-z0-9_-' '-')"
    local name
    name="$(date +%Y-%m-%d_%H-%M-%S)${label:+_$label}"
    local work="$BACKUP_ROOT/$name.partial"
    mkdir -p "$work"

    for db in "${DATABASES[@]}"; do
        if ! db_exists "$db"; then
            echo "  - $db: does not exist yet, skipped"
            continue
        fi
        echo "  - $db"
        mysqldump -h "$DB_HOST" -uroot \
            --single-transaction --quick --routines --triggers --events \
            --add-drop-database --databases "$db" \
            | gzip -c > "$work/$db.sql.gz"
    done

    # Server config files and .env (contains the DB password, keep backups private).
    tar -czf "$work/config.tar.gz" -C /wowps config .env 2>/dev/null \
        || tar -czf "$work/config.tar.gz" -C /wowps config

    mv "$work" "$BACKUP_ROOT/$name"
    echo "Backup saved: backups/$name"

    # Retention: keep the newest BACKUP_KEEP backups (0 = keep all).
    local keep="${BACKUP_KEEP:-10}"
    case "$keep" in '' | *[!0-9]*) keep=10 ;; esac
    if [ "$keep" -gt 0 ]; then
        local total
        total="$(list_backups | wc -l)"
        if [ "$total" -gt "$keep" ]; then
            list_backups | head -n "$((total - keep))" | while read -r old; do
                echo "Removing old backup: backups/$old"
                rm -rf "${BACKUP_ROOT:?}/$old"
            done
        fi
    fi
}

cmd_restore() {
    local name="${1:-}"
    if [ -z "$name" ] || [ ! -d "$BACKUP_ROOT/$name" ]; then
        echo "ERROR: backup '$name' not found. Available backups:" >&2
        list_backups >&2
        exit 1
    fi

    local found=0
    for db in "${DATABASES[@]}"; do
        local file="$BACKUP_ROOT/$name/$db.sql.gz"
        [ -f "$file" ] || continue
        found=1
        echo "  - restoring $db"
        gunzip -c "$file" | mysql_cmd
    done

    if [ "$found" -eq 0 ]; then
        echo "ERROR: no database dumps in backups/$name" >&2
        exit 1
    fi
    echo "Restore finished from backups/$name"
}

case "${1:-}" in
    backup) shift; cmd_backup "$@" ;;
    restore) shift; cmd_restore "$@" ;;
    list) list_backups ;;
    *)
        echo "usage: db-tools.sh backup [label] | restore <name> | list" >&2
        exit 2
        ;;
esac
