#!/usr/bin/env bash
# Shared helpers for the wowps bash scripts. Sourced, not run directly.
# Works with bash 3.2 (macOS) and newer.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="$ROOT_DIR/.env"
ENV_EXAMPLE="$ROOT_DIR/.env.example"
VERSIONS_FILE="$ROOT_DIR/versions.env"
SOURCE_DIR="$ROOT_DIR/source"
AC_DIR="$SOURCE_DIR/azerothcore-wotlk"
PB_DIR="$AC_DIR/modules/mod-playerbots"
DB_VOLUME="wowps_ac-database"
IMAGES="wowps-ac-worldserver:local wowps-ac-authserver:local wowps-ac-db-import:local wowps-ac-client-data:local"
BUILD_SERVICES="ac-client-data-init ac-db-import ac-authserver ac-worldserver"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_BLUE=$'\033[1;34m' C_GREEN=$'\033[1;32m' C_YELLOW=$'\033[1;33m' C_RED=$'\033[1;31m' C_OFF=$'\033[0m'
else
    C_BLUE='' C_GREEN='' C_YELLOW='' C_RED='' C_OFF=''
fi
info() { printf '%s==>%s %s\n' "$C_BLUE" "$C_OFF" "$*"; }
ok() { printf '%sOK:%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf '%sWARNING:%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die() {
    printf '%sERROR:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# .env / versions.env reading and writing (never `source`d: values may
# contain spaces, and these files are data, not scripts)
# ---------------------------------------------------------------------------

# env_get KEY [FILE] [DEFAULT]
env_get() {
    local key="$1" file="${2:-$ENV_FILE}" default="${3:-}" line value
    if [ ! -f "$file" ]; then
        printf '%s' "$default"
        return 0
    fi
    line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" | tail -n 1 || true)"
    if [ -z "$line" ]; then
        printf '%s' "$default"
        return 0
    fi
    value="${line#*=}"
    value="${value%$'\r'}"
    value="${value#"${value%%[![:space:]]*}"}"
    case "$value" in
        \"*\") value="${value#\"}" && value="${value%\"}" ;;
        \'*\') value="${value#\'}" && value="${value%\'}" ;;
        *) value="${value%%[[:space:]]#*}" ;;
    esac
    value="${value%"${value##*[![:space:]]}"}"
    [ -n "$value" ] || value="$default"
    printf '%s' "$value"
}

# env_set KEY VALUE [FILE]  (replaces the line, or appends it; keeps file permissions)
env_set() {
    local key="$1" value="$2" file="${3:-$ENV_FILE}" tmp
    tmp="$(mktemp)"
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
        awk -v k="$key" -v v="$value" '
            !done && $0 ~ ("^[[:space:]]*" k "[[:space:]]*=") { print k "=" v; done = 1; next }
            { print }
        ' "$file" >"$tmp"
    else
        cat "$file" >"$tmp"
        printf '%s=%s\n' "$key" "$value" >>"$tmp"
    fi
    cat "$tmp" >"$file"
    rm -f "$tmp"
}

read_versions() {
    [ -f "$VERSIONS_FILE" ] || die "versions.env is missing. Re-download this repository."
    AC_REPO="$(env_get AC_REPO "$VERSIONS_FILE")"
    # shellcheck disable=SC2034  # AC_BRANCH / PLAYERBOTS_BRANCH are used by update.sh
    AC_BRANCH="$(env_get AC_BRANCH "$VERSIONS_FILE")"
    AC_COMMIT="$(env_get AC_COMMIT "$VERSIONS_FILE")"
    PLAYERBOTS_REPO="$(env_get PLAYERBOTS_REPO "$VERSIONS_FILE")"
    # shellcheck disable=SC2034
    PLAYERBOTS_BRANCH="$(env_get PLAYERBOTS_BRANCH "$VERSIONS_FILE")"
    PLAYERBOTS_COMMIT="$(env_get PLAYERBOTS_COMMIT "$VERSIONS_FILE")"
    local v
    for v in AC_REPO AC_COMMIT PLAYERBOTS_REPO PLAYERBOTS_COMMIT; do
        [ -n "${!v}" ] || die "$v is missing from versions.env."
    done
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
require_docker() {
    command -v docker >/dev/null 2>&1 \
        || die "Docker is not installed. Install Docker Desktop (Windows/macOS) or Docker Engine (Linux), see README."
    docker info >/dev/null 2>&1 \
        || die "Docker is installed but not running (or you lack permission). Start Docker Desktop / the docker service and try again."
    docker compose version >/dev/null 2>&1 \
        || die "'docker compose' (Compose v2) is missing. Update Docker, see README."
}

require_git() {
    command -v git >/dev/null 2>&1 || die "git is not installed. See the README prerequisites."
}

require_env() {
    [ -f "$ENV_FILE" ] || die "No .env file. Run ./setup.sh first."
}

images_exist() {
    # shellcheck disable=SC2086
    docker image inspect $IMAGES >/dev/null 2>&1
}

require_images() {
    images_exist || die "Server images are not built yet. Run ./setup.sh first."
}

container_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || true)" = "true" ]
}

db_volume_exists() {
    docker volume inspect "$DB_VOLUME" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Setup helpers
# ---------------------------------------------------------------------------
random_password() {
    # Letters and digits only: safe in .env, in the DB connection strings and in SQL.
    (
        set +o pipefail
        LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
    )
}

is_linux() { [ "$(uname -s)" = "Linux" ]; }

# Create .env from .env.example if needed, and fill in generated values.
ensure_env_file() {
    local created=0
    if [ ! -f "$ENV_FILE" ]; then
        [ -f "$ENV_EXAMPLE" ] || die ".env.example is missing. Re-download this repository."
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        chmod 600 "$ENV_FILE" 2>/dev/null || true
        created=1
        ok "Created .env from .env.example"
    fi

    local pw
    pw="$(env_get DB_ROOT_PASSWORD)"
    if [ -z "$pw" ] || [ "$pw" = "change-me" ]; then
        if db_volume_exists; then
            die "A database from an earlier install already exists (Docker volume $DB_VOLUME), but .env has no password for it.
       Put the old password into .env as DB_ROOT_PASSWORD=...
       or, to throw the old database away (deletes all accounts and characters!):
         docker volume rm $DB_VOLUME"
        fi
        env_set DB_ROOT_PASSWORD "$(random_password)"
        ok "Generated a random database password (saved in .env)"
    elif ! printf '%s' "$pw" | grep -qE '^[A-Za-z0-9._-]+$'; then
        die "DB_ROOT_PASSWORD in .env may only contain letters, numbers, '.', '_' and '-'."
    fi

    # On Linux the containers must write to ./config and ./logs as your user.
    if is_linux; then
        local uid gid
        uid="$(id -u)"
        gid="$(id -g)"
        # Root or system accounts: use 1000 and hand the folders to it (see ensure_dirs).
        [ "$uid" -ge 1000 ] || uid=1000
        [ "$gid" -ge 1000 ] || gid=1000
        if [ "$created" -eq 1 ] || [ "$(env_get DOCKER_USER_ID)" = "1000" ]; then
            env_set DOCKER_USER_ID "$uid"
            env_set DOCKER_GROUP_ID "$gid"
        fi
    fi
}

# Folders that are bind-mounted into the containers.
ensure_dirs() {
    mkdir -p "$ROOT_DIR/config" "$ROOT_DIR/logs" "$ROOT_DIR/backups"
    if is_linux; then
        local uid gid
        uid="$(env_get DOCKER_USER_ID "" 1000)"
        gid="$(env_get DOCKER_GROUP_ID "" 1000)"
        if [ "$(id -u)" -eq 0 ]; then
            chown -R "$uid:$gid" "$ROOT_DIR/config" "$ROOT_DIR/logs" "$ROOT_DIR/backups"
        elif [ "$(id -u)" != "$uid" ]; then
            warn "The server runs as user ID $uid but you are $(id -u). If it can't write to config/ or logs/, run:
       sudo chown -R $uid:$gid config logs backups"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Source checkout (pinned commits)
# ---------------------------------------------------------------------------

# Print the commit a checkout is on, or nothing.
source_commit() {
    git -C "$1" rev-parse -q --verify HEAD 2>/dev/null || true
}

# checkout_commit DIR URL COMMIT: make DIR a shallow checkout of exactly COMMIT.
checkout_commit() {
    local dir="$1" url="$2" commit="$3"
    if [ ! -d "$dir/.git" ]; then
        mkdir -p "$dir"
        git -C "$dir" init -q
        git -C "$dir" config core.autocrlf false
        git -C "$dir" remote add origin "$url"
    else
        git -C "$dir" remote set-url origin "$url"
    fi

    if [ "$(source_commit "$dir")" != "$commit" ]; then
        info "Downloading $(basename "$dir") @ ${commit:0:12} ..."
        git -C "$dir" fetch --depth 1 origin "$commit" \
            || die "Could not download commit $commit from $url. Check your internet connection and the commit in versions.env."
    fi
    # --force also undoes any local edits to tracked files in the checkout.
    git -C "$dir" -c advice.detachedHead=false checkout -q --force "$commit" \
        || die "Could not check out $commit in $dir."
}

sync_sources() {
    read_versions
    mkdir -p "$SOURCE_DIR"
    checkout_commit "$AC_DIR" "$AC_REPO" "$AC_COMMIT"
    checkout_commit "$PB_DIR" "$PLAYERBOTS_REPO" "$PLAYERBOTS_COMMIT"
    ok "Source is at AzerothCore ${AC_COMMIT:0:12} + mod-playerbots ${PLAYERBOTS_COMMIT:0:12}"
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

# Parallel compile jobs: BUILD_JOBS from .env, or derived from what Docker has
# (CPUs, and ~2 GB of memory per job so the compiler doesn't run out of RAM).
build_jobs() {
    local jobs cpus mem by_mem
    jobs="$(env_get BUILD_JOBS)"
    if printf '%s' "$jobs" | grep -qE '^[1-9][0-9]*$'; then
        printf '%s' "$jobs"
        return 0
    fi
    cpus="$(docker info --format '{{.NCPU}}' 2>/dev/null || echo 2)"
    mem="$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 4294967296)"
    by_mem=$((mem / 2147483648))
    jobs="$cpus"
    [ "$by_mem" -lt "$jobs" ] && jobs="$by_mem"
    [ "$jobs" -ge 1 ] || jobs=1
    printf '%s' "$jobs"
}

# Copy upstream's Dockerfile to Dockerfile.wowps with a fixed number of compile
# jobs (upstream always uses all CPUs + 1, which can run out of memory).
generate_dockerfile() {
    local jobs="$1"
    local src="$AC_DIR/apps/docker/Dockerfile"
    local dst="$AC_DIR/apps/docker/Dockerfile.wowps"
    # shellcheck disable=SC2016  # literal text from upstream's Dockerfile
    local pattern='-j $(($(nproc) + 1))'
    [ -f "$src" ] || die "$src not found. Is the source checkout complete? Run ./setup.sh again."
    local content
    content="$(cat "$src")"
    if grep -qF -- "$pattern" "$src"; then
        printf '%s\n' "${content//"$pattern"/-j $jobs}" >"$dst"
    else
        warn "Upstream Dockerfile changed; can't set BUILD_JOBS. Building with upstream's default."
        printf '%s\n' "$content" >"$dst"
    fi
}

build_images() {
    local jobs
    jobs="$(build_jobs)"
    generate_dockerfile "$jobs"
    info "Building server images with $jobs parallel jobs. The first build takes 30-90 minutes..."
    # shellcheck disable=SC2086
    docker compose build $BUILD_SERVICES
}

download_client_data() {
    info "Downloading map data (dbc/maps/vmaps/mmaps, ~1.2 GB) if needed..."
    docker compose run --rm -T ac-client-data-init \
        || die "Downloading the map data failed. Check your internet connection and run the script again."
}

# Run the backup/restore helper container (-T: no terminal needed, works from cron).
db_tools() {
    docker compose --profile tools run --rm -T ac-db-tools "$@"
}

# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------

# Show the last log lines of any one-shot container that failed.
show_failed_oneshots() {
    local svc code
    for svc in ac-client-data-init ac-db-import ac-realmlist; do
        code="$(docker inspect -f '{{.State.ExitCode}}' "$svc" 2>/dev/null || true)"
        if [ -n "$code" ] && [ "$code" != "0" ]; then
            warn "$svc failed (exit code $code). Last log lines:"
            docker logs --tail 40 "$svc" 2>&1 || true
        fi
    done
}

# Wait until the worldserver logs "ready", printing progress. Returns 1 if it
# stops or crashes, or after TIMEOUT seconds (default 30 min).
wait_for_worldserver() {
    local timeout="${1:-1800}" waited=0 started restarts status last
    started="$(docker inspect -f '{{.State.StartedAt}}' ac-worldserver)"
    restarts="$(docker inspect -f '{{.RestartCount}}' ac-worldserver)"
    while :; do
        # (no `grep -q`: with pipefail an early grep exit can fail the pipeline)
        if docker logs --since "$started" ac-worldserver 2>&1 | grep -F '(worldserver-daemon) ready' >/dev/null; then
            return 0
        fi
        status="$(docker inspect -f '{{.State.Status}}' ac-worldserver 2>/dev/null || echo missing)"
        if [ "$status" != "running" ] || [ "$(docker inspect -f '{{.RestartCount}}' ac-worldserver)" != "$restarts" ]; then
            warn "The worldserver stopped while starting (status: $status). Last log lines:"
            docker logs --tail 60 ac-worldserver 2>&1 || true
            return 1
        fi
        if [ "$waited" -ge "$timeout" ]; then
            warn "The worldserver is still not ready after $((timeout / 60)) minutes."
            return 1
        fi
        if [ $((waited % 20)) -eq 0 ]; then
            last="$(docker logs --tail 1 ac-worldserver 2>&1 | tr -d '\r' | cut -c1-100 || true)"
            printf '   ... %s\n' "${last:-starting}"
        fi
        sleep 5
        waited=$((waited + 5))
    done
}

print_connect_info() {
    local address port name
    address="$(env_get REALM_ADDRESS "" 127.0.0.1)"
    port="$(env_get AUTH_PORT "" 3724)"
    name="$(env_get REALM_NAME "" "AzerothCore Playerbots")"
    echo
    ok "Server is running: realm '$name' at $address"
    echo "   In your WoW 3.3.5a folder, open Data/<your language, e.g. enUS>/realmlist.wtf"
    if [ "$port" = "3724" ]; then
        echo "   and make it contain exactly:  set realmlist $address"
    else
        echo "   and make it contain exactly:  set realmlist $address:$port"
    fi
    echo "   No account yet? See 'Create your game account' in the README."
    echo "   Server console: docker attach ac-worldserver  (leave it with Ctrl+P then Ctrl+Q)"
}

lan_ip() {
    local ip=""
    if command -v ip >/dev/null 2>&1; then
        ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}' | head -n 1 || true)"
    fi
    if [ -z "$ip" ] && command -v ipconfig >/dev/null 2>&1; then
        ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
    fi
    printf '%s' "$ip"
}
