#!/usr/bin/env bash
# Open the world server console, where you type GM commands such as
#   account create NAME PASSWORD
#   account set gmlevel NAME 3 -1
# Press Ctrl+C to leave. The server keeps running.
#
# Usage: ./console.sh
source "$(dirname "$0")/scripts/lib.sh"

case "${1:-}" in
    -h | --help)
        sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

require_docker
container_running ac-worldserver || die "The server is not running. Start it with ./start.sh"

echo "Connected to the server console. Type a command and press Enter, e.g."
echo "    account create myname mypassword"
echo "    account set gmlevel myname 3 -1"
echo "Press Enter once to see the AC> prompt. Press Ctrl+C to leave (the server keeps running)."
echo
# Ctrl+C is turned into "detach" so it can't shut the server down by accident.
docker attach --detach-keys=ctrl-c ac-worldserver || true
echo
ok "Left the console. The server is still running."
