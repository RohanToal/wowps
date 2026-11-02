#!/usr/bin/env bash
# Start the server (database, auth server, world server) and wait until the
# world is ready. The first start takes longer: it creates the databases and,
# with bots enabled, creates the bot accounts and characters.
#
# Usage: ./start.sh
source "$(dirname "$0")/scripts/lib.sh"

case "${1:-}" in
    -h | --help)
        sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

require_docker
require_env
require_images
ensure_dirs

if ! db_volume_exists; then
    info "First start: creating the databases. This takes a few minutes..."
fi

info "Starting the server..."
if ! docker compose up -d --no-build --remove-orphans; then
    show_failed_oneshots
    die "The server could not start. See the messages above, and 'Troubleshooting' in the README."
fi

info "Waiting for the world server to finish loading (with many bots this can take several minutes)..."
if ! wait_for_worldserver; then
    die "The world server did not start. Full log: docker logs ac-worldserver   (or logs/Server.log)"
fi

print_connect_info
