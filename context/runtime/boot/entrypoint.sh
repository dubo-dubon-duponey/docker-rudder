#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

[ -w /certs ] || {
  printf >&2 "/certs is not writable. Check your mount permissions.\n"
  exit 1
}

[ -w /tmp ] || {
  printf >&2 "/tmp is not writable. Check your mount permissions.\n"
  exit 1
}

[ -w /data ] || {
  printf >&2 "/data is not writable. Check your mount permissions.\n"
  exit 1
}

# Helpers
case "${1:-run}" in
  # Short hand helper to generate password hash
  "hash")
    shift
    printf >&2 "Generating password hash\n"
    caddy hash-password -algorithm bcrypt "$@"
    exit
  ;;
  # Helper to get the ca.crt out (once initialized)
  "cert")
    if [ "$TLS" == "" ]; then
      printf >&2 "Your container is not configured for TLS termination - there is no local CA in that case."
      exit 1
    fi
    if [ "$TLS" != "internal" ]; then
      printf >&2 "Your container uses letsencrypt - there is no local CA in that case."
      exit 1
    fi
    if [ ! -e /certs/pki/authorities/local/root.crt ]; then
      printf >&2 "No root certificate installed or generated. Run the container so that a cert is generated, or provide one at runtime."
      exit 1
    fi
    cat /certs/pki/authorities/local/root.crt
    exit
  ;;
  "run")
    # Bonjour the container if asked to. While the PORT is no guaranteed to be mapped on the host in bridge, this does not matter since mDNS will not work at all in bridge mode.
    if [ "${MDNS_ENABLED:-}" == true ]; then
      goello-server -name "$MDNS_NAME" -host "$MDNS_HOST" -port "$PORT" -type "$MDNS_TYPE" &
    fi

    # Given how the caddy conf is set right now, we cannot have these be not set, so, stuff in randomized shit in there in case there is nothing
    #readonly USERNAME="${USERNAME:-"$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)"}"
    #readonly PASSWORD="${PASSWORD:-$(caddy hash-password -algorithm bcrypt -plaintext "$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)")}"
    # If we want TLS and authentication, start caddy in the background
    if [ "$TLS" ]; then
      HOME=/tmp/caddy-home exec caddy run -config /config/caddy/main.conf --adapter caddyfile &
    fi
  ;;
esac


# System constants
export RSERVER_GATEWAY_WEB_PORT="42042"
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
