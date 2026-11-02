#!/usr/bin/env bash
# Runs inside a throwaway MySQL container every time the server starts.
# Copies REALM_NAME, REALM_ADDRESS and WORLD_PORT from .env into the realm list
# (acore_auth.realmlist), so the realm shows the right name and clients connect
# to the right address.
set -euo pipefail

# Escape a value for use inside a single-quoted SQL string.
sql_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g"
}

name="${REALM_NAME:-AzerothCore Playerbots}"
address="${REALM_ADDRESS:-127.0.0.1}"
port="${REALM_PORT:-8085}"

case "$port" in
    '' | *[!0-9]*)
        echo "ERROR: WORLD_PORT must be a number, got '$port'." >&2
        exit 1
        ;;
esac

# localAddress is set to the same value as address on purpose. Behind Docker's
# port forwarding the auth server can't reliably tell LAN clients from internet
# clients, so every client gets the same address.
mysql -h ac-database -uroot acore_auth -e "
UPDATE realmlist
   SET name = '$(sql_escape "$name")',
       address = '$(sql_escape "$address")',
       localAddress = '$(sql_escape "$address")',
       port = $port
 WHERE id = 1;"

echo "Realm list updated: '$name' at $address:$port"
