#!/usr/bin/env bash
# Update the server to the commits pinned in versions.env.
#
#   ./update.sh            build the versions in versions.env (do a `git pull`
#                          of this repo first to get newer pins)
#   ./update.sh --latest   move the pins to the newest upstream commits first
#   ./update.sh --rebuild  rebuild even if nothing changed
#
# Order of work: download source -> build new images (server keeps running)
# -> back up -> stop -> update map data if needed -> start (database updates are
# applied automatically on start). If the build fails, the previous source and
# pins are put back and your server is untouched.
source "$(dirname "$0")/scripts/lib.sh"

latest=0
rebuild=0
for arg in "$@"; do
    case "$arg" in
        --latest) latest=1 ;;
        --rebuild) rebuild=1 ;;
        -h | --help)
            sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "Unknown option '$arg'. See ./update.sh --help" ;;
    esac
done

require_git
require_docker
require_env
[ -d "$AC_DIR/.git" ] || die "No source checkout found. Run ./setup.sh first."
ensure_dirs

old_versions="$(cat "$VERSIONS_FILE")"
old_ac="$(source_commit "$AC_DIR")"
old_pb="$(source_commit "$PB_DIR")"

if [ "$latest" -eq 1 ]; then
    read_versions
    info "Looking up the newest upstream commits..."
    new_ac="$(git ls-remote "$AC_REPO" "refs/heads/$AC_BRANCH" | cut -f1)"
    new_pb="$(git ls-remote "$PLAYERBOTS_REPO" "refs/heads/$PLAYERBOTS_BRANCH" | cut -f1)"
    [ -n "$new_ac" ] && [ -n "$new_pb" ] || die "Could not look up upstream branches. Check your internet connection."
    env_set AC_COMMIT "$new_ac" "$VERSIONS_FILE"
    env_set PLAYERBOTS_COMMIT "$new_pb" "$VERSIONS_FILE"
    echo "   AzerothCore:    ${AC_COMMIT:0:12} -> ${new_ac:0:12}"
    echo "   mod-playerbots: ${PLAYERBOTS_COMMIT:0:12} -> ${new_pb:0:12}"
    warn "These newer commits have not been tested together by this repo."
fi

read_versions
if [ "$old_ac" = "$AC_COMMIT" ] && [ "$old_pb" = "$PLAYERBOTS_COMMIT" ] && images_exist && [ "$rebuild" -eq 0 ]; then
    ok "Already up to date (AzerothCore ${AC_COMMIT:0:12}, mod-playerbots ${PLAYERBOTS_COMMIT:0:12})."
    exit 0
fi

rollback() {
    warn "Putting the previous source and versions.env back..."
    printf '%s\n' "$old_versions" >"$VERSIONS_FILE"
    [ -n "$old_ac" ] && checkout_commit "$AC_DIR" "$AC_REPO" "$old_ac"
    [ -n "$old_pb" ] && checkout_commit "$PB_DIR" "$PLAYERBOTS_REPO" "$old_pb"
    generate_dockerfile "$(build_jobs)"
}

info "Getting the new source code..."
if ! (sync_sources); then
    rollback
    die "Download failed. Nothing was changed."
fi

if ! build_images; then
    rollback
    die "The build failed, so the update was cancelled. Your server still runs the previous version.
       If you used --latest, upstream may be broken right now: try again in a few days, or
       stay on the versions this repo pins. If the log says 'Killed', set BUILD_JOBS=2 in .env."
fi
ok "New images built."

was_running=0
container_running ac-worldserver && was_running=1

if db_volume_exists; then
    info "Backing up before applying the update..."
    db_was_running=0
    container_running ac-database && db_was_running=1
    db_tools backup before-update
    [ "$db_was_running" -eq 1 ] || docker compose down >/dev/null 2>&1 || true
fi

if [ "$was_running" -eq 1 ]; then
    info "Stopping the server..."
    docker compose down --remove-orphans
fi

download_client_data

ok "Update installed: AzerothCore ${AC_COMMIT:0:12}, mod-playerbots ${PLAYERBOTS_COMMIT:0:12}."
if [ "$was_running" -eq 1 ]; then
    "$ROOT_DIR/start.sh"
else
    echo "Start the server with ./start.sh (database updates are applied on start)."
fi
