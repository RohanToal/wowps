#!/usr/bin/env bash
# Stop the server. The world server saves all characters first, which can take
# a minute with many bots. Accounts, characters and settings are kept.
#
# Usage: ./stop.sh
source "$(dirname "$0")/scripts/lib.sh"

case "${1:-}" in
    -h | --help)
        sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

require_docker
require_env

info "Stopping the server (saving characters first)..."
docker compose down --remove-orphans
ok "Server stopped."
