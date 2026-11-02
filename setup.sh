#!/usr/bin/env bash
# First-time setup (safe to run again):
#   1. checks Docker and git
#   2. creates .env with a random database password
#   3. downloads the pinned AzerothCore + mod-playerbots source into ./source
#   4. downloads the server map data into a Docker volume
#   5. builds the server images (takes a while the first time)
#
# Usage: ./setup.sh
source "$(dirname "$0")/scripts/lib.sh"

case "${1:-}" in
    -h | --help)
        sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

echo "=============================================================="
echo " WoW 3.3.5a personal server: AzerothCore + mod-playerbots"
echo "=============================================================="

info "Checking prerequisites..."
require_git
require_docker
ok "git and Docker found"

info "Preparing settings..."
ensure_env_file
ensure_dirs

info "Getting the pinned server source code..."
sync_sources

# Build the small download image first so a network problem shows up before
# the long compile.
generate_dockerfile "$(build_jobs)"
info "Preparing the map data downloader..."
docker compose build ac-client-data-init
download_client_data

build_images

echo
ok "Setup finished."
echo
echo "Next steps:"
echo "  1. (optional) Edit .env: realm name, bot counts, REALM_ADDRESS for LAN play."
ip="$(lan_ip)"
if [ -n "$ip" ]; then
    echo "     This computer's LAN IP looks like: $ip"
fi
echo "  2. Start the server:        ./start.sh"
echo "  3. Create your account:     see 'Create your game account' in README.md"
