#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)"
readonly root
# shellcheck source=/dev/null
source "$root/helpers.sh"
# shellcheck source=/dev/null
source "$root/mdns.sh"

helpers::dir::writable "/certs"
helpers::dir::writable "/data"
helpers::dir::writable "/tmp"
helpers::dir::writable "$XDG_RUNTIME_DIR" create
helpers::dir::writable "$XDG_STATE_HOME" create
helpers::dir::writable "$XDG_CACHE_HOME" create

# mDNS blast if asked to
[ ! "${MDNS_HOST:-}" ] || {
  _mdns_port="$([ "$TLS" != "" ] && printf "%s" "${PORT_HTTPS:-443}" || printf "%s" "${PORT_HTTP:-80}")"
  [ ! "${MDNS_STATION:-}" ] || mdns::add "_workstation._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "$_mdns_port"
  mdns::add "${MDNS_TYPE:-_http._tcp}" "$MDNS_HOST" "${MDNS_NAME:-}" "$_mdns_port"
  mdns::start &
}

# Start the sidecar
start::sidecar &

# System constants
export RSERVER_GATEWAY_WEB_PORT="10042"
# Rudder server is susceptible...
LOG_LEVEL="$(printf "%s" "${LOG_LEVEL:-info}" | tr '[:lower:]' '[:upper:]')"
export LOG_LEVEL

#if [ "${USERNAME:-}" ]; then
#  export REGISTRY_AUTH=htpasswd
#  export REGISTRY_AUTH_HTPASSWD_REALM="$REALM"
#  export REGISTRY_AUTH_HTPASSWD_PATH=/data/htpasswd
#  printf "%s:%s\n" "$USERNAME" "$(printf "%s" "$PASSWORD" | base64 -d)" > /data/htpasswd
#fi

# args=()

# XXX BROKEN AF
if command -v rudder >/dev/null; then
  # Rudder server is raw
  exec rudder "$@"
fi
