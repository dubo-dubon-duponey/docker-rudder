#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

# Ensure the data folder is writable
[ -w "/data" ] || {
  >&2 printf "/data is not writable. Check your mount permissions.\n"
  exit 1
}

# System constants
export RSERVER_GATEWAY_WEB_PORT="${PORT:-}"
# Rudder server is susceptible...
LOG_LEVEL="$(printf "%s" "${LOG_LEVEL:-info}" | tr '[:lower:]' '[:upper:]')"
export LOG_LEVEL

if [ "${USERNAME:-}" ]; then
  export REGISTRY_AUTH=htpasswd
  export REGISTRY_AUTH_HTPASSWD_REALM="$REALM"
  export REGISTRY_AUTH_HTPASSWD_PATH=/data/htpasswd
  printf "%s:%s\n" "$USERNAME" "$(printf "%s" "$PASSWORD" | base64 -d)" > /data/htpasswd
fi

# args=()

# Bonjour the container if we have a name
if [ "${MDNS_NAME:-}" ]; then
  goello-server -name "$MDNS_NAME" -host "$MDNS_HOST" -port "$PORT" -type "$MDNS_TYPE" &
fi

if command -v rudder >/dev/null; then
  # Rudder server is raw
  exec rudder "$@"
else
  # Rudder config is hidden behind Caddy
  exec caddy run -config /config/caddy/main.conf --adapter caddyfile "$@"
fi
