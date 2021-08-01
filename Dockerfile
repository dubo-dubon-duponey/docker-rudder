ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-07-01@sha256:f1c46316c38cc1ca54fd53b54b73797b35ba65ee727beea1a5ed08d0ad7e8ccf
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-07-01@sha256:9f5b20d392e1a1082799b3befddca68cee2636c72c502aa7652d160896f85b36
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-07-01@sha256:f1e25694fe933c7970773cb323975bb5c995fa91d0c1a148f4f1c131cbc5872c
ARG           FROM_IMAGE_NODE=base:node-bullseye-2021-07-01@sha256:d201555186aa4982ba6aa48fb283d2ce5e74e50379a7b9e960c22a10ee23ba54

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools
FROM          $FROM_REGISTRY/$FROM_IMAGE_NODE                                                                           AS builder-node

#######################
# Fetcher
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-main

ENV           GIT_REPO=github.com/rudderlabs/rudder-server
ENV           GIT_VERSION=3ac155b
ENV           GIT_COMMIT=3ac155b775f9cc1a2eacef8aab035c27705463df

ENV           WITH_BUILD_SOURCE="./main.go"
ENV           WITH_BUILD_OUTPUT="rudder"

ENV           WITH_LDFLAGS="-X main.Version=$GIT_VERSION"

RUN           git clone --recurse-submodules git://"$GIT_REPO" .
RUN           git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download

#######################
# Main builder
#######################
FROM          --platform=$BUILDPLATFORM fetcher-main                                                                    AS builder-main

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

# Important cases being handled:
# - cannot compile statically with PIE but on amd64 and arm64
# - cannot compile fully statically with NETCGO
RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i386/")")"; \
                export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
                export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
                export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
                export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
                [ ! "${ENABLE_STATIC:-}" ] || { \
                  [ ! "${WITH_CGO_NET:-}" ] || { \
                    ENABLE_STATIC=; \
                    LDFLAGS="${LDFLAGS:-} -static-libgcc -static-libstdc++"; \
                  }; \
                  [ "$GOARCH" == "amd64" ] || [ "$GOARCH" == "arm64" ] || [ "${ENABLE_PIE:-}" != true ] || ENABLE_STATIC=; \
                }; \
                WITH_LDFLAGS="${WITH_LDFLAGS:-} -linkmode=external -extld="$CC" -extldflags \"${LDFLAGS:-} ${ENABLE_STATIC:+-static}${ENABLE_PIE:+-pie}\""; \
                WITH_TAGS="${WITH_TAGS:-} cgo ${ENABLE_STATIC:+static static_build}"; \
              }; \
              go build -ldflags "-s -w -v ${WITH_LDFLAGS:-}" -tags "${WITH_TAGS:-} net${WITH_CGO_NET:+c}go osusergo" -o /dist/boot/bin/"$WITH_BUILD_OUTPUT" "$WITH_BUILD_SOURCE"

#######################
# Config generator: https://github.com/rudderlabs/rudder-server/wiki/RudderStack-Config-Generator
#######################
FROM          --platform=$BUILDPLATFORM fetcher-main                                                                    AS builder-main-config

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT

COPY          --from=builder-node /usr/local/bin/node /dist/boot/bin/node
COPY          --from=builder-node /usr/local/bin/node /dist/boot/bin/nodejs
COPY          --from=builder-node /usr/local/bin/yarn /dist/boot/bin/yarn
COPY          --from=builder-node /usr/local/bin/yarn /dist/boot/bin/yarnpkg

ARG           npm_config_arch=$TARGETARCH

# XXX node-gyp is bollocks
#ENV           USER=root
RUN           mkdir -p /tmp/.npm-global
ENV           PATH=/tmp/.npm-global/bin:$PATH
ENV           NPM_CONFIG_PREFIX=/tmp/.npm-global

WORKDIR       /source/utils/config-gen
RUN           npm install
RUN           yarn build
RUN           mkdir -p /dist/boot/bin
RUN           mv "$GOPATH/src/$GIT_REPO/utils/config-gen/build" /dist/boot/bin/configurator

# XXX to start:
# ./node_modules/.bin/react-app-rewired start

#######################
# Builder assembly
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS builder-assembly-server

COPY          --from=builder-main   /dist/boot /dist/boot

COPY          --from=builder-tools  /boot/bin/goello-server  /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/caddy          /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health    /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Builder assembly
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS builder-assembly-config

COPY          --from=builder-main-config /dist/boot/bin /dist/boot/bin

COPY          --from=builder-tools  /boot/bin/goello-server  /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/caddy          /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health    /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image, server
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME                                                                        AS server

COPY          --from=builder-assembly-server --chown=$BUILD_UID:root /dist /

EXPOSE        5000

# VOLUME        /data
VOLUME        /tmp

# mDNS
ENV           MDNS_NAME="Rudder Server mDNS display name"
ENV           MDNS_HOST="rudder-server"
ENV           MDNS_TYPE=_http._tcp

# Realm in case access is authenticated
ENV           REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           USERNAME=""
ENV           PASSWORD=""

# Log level and port
ENV           LOG_LEVEL=warn
ENV           PORT=5000

# https://github.com/rudderlabs/rudder-server/blob/master/build/docker.env
ENV           RSERVER_BACKEND_CONFIG_CONFIG_FROM_FILE=true
ENV           RSERVER_BACKEND_CONFIG_CONFIG_JSONPATH=/config/workspaceConfig.json
ENV           JOBS_DB_USER=rudder
ENV           JOBS_DB_PORT=5432
ENV           JOBS_DB_DB_NAME=jobsdb
ENV           JOBS_DB_PASSWORD=password
ENV           DEST_TRANSFORM_URL=http://rudder-transformer:4000
ENV           JOBS_DB_HOST=rudder-db
# ENV           CONFIG_BACKEND_URL=https://api.rudderlabs.com -e WORKSPACE_TOKEN=1iZJ4g6d3ktmvwAjodOhUg0XtCf -e
ENV           CONFIG_PATH=/config/server.toml

ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1

#######################
# Running image, configurator
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME                                                                        AS config

COPY          --from=builder-assembly-config --chown=$BUILD_UID:root /dist /

EXPOSE        3000

# mDNS
ENV           MDNS_NAME="Rudder Config mDNS display name"
ENV           MDNS_HOST="rudder-config"
ENV           MDNS_TYPE=_http._tcp

# XXX incomplete - miss domain et al
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt
ENV           TLS="internal"
# Either require_and_verify or verify_if_given
ENV           MTLS_MODE="verify_if_given"

# Realm in case access is authenticated
ENV           REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           USERNAME=""
ENV           PASSWORD=""

# Log level and port
ENV           LOG_LEVEL=warn
ENV           PORT=4443

ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
