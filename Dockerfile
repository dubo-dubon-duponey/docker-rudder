ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-10-15@sha256:33e021267790132e63be2cea08e77d64ec5d0434355734e94f8ff2d90c6f8944
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2021-10-15@sha256:eb822683575d68ccbdf62b092e1715c676b9650a695d8c0235db4ed5de3e8534
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-10-15@sha256:7072702dab130c1bbff5e5c4a0adac9c9f2ef59614f24e7ee43d8730fae2764c
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-10-15@sha256:e8ec2d1d185177605736ba594027f27334e68d7984bbfe708a0b37f4b6f2dbd7
ARG           FROM_IMAGE_NODE=base:node-bullseye-2021-10-15@sha256:7147b869d742a33a9a761163e02766bd2eb5a118011d37c2cc8ec6b415fd13c7

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools
FROM          $FROM_REGISTRY/$FROM_IMAGE_NODE                                                                           AS builder-node

#######################
# Fetcher
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-main

ARG           GIT_REPO=github.com/rudderlabs/rudder-server
ARG           GIT_VERSION=5b86152
ARG           GIT_COMMIT=5b86152532955d1a9554ed8556e13807ff2001eb

ENV           WITH_BUILD_SOURCE="./main.go"
ENV           WITH_BUILD_OUTPUT="rudder"

ENV           WITH_LDFLAGS="-X main.Version=$GIT_VERSION"

RUN           git clone git://"$GIT_REPO" .; git checkout "$GIT_COMMIT"
RUN           sed -Ei 's/git@github.com:/git:\/\/github.com\//g' .gitmodules
RUN           git submodule update --init --recursive
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

RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
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
ENV           PATH=/tmp/.npm-global/bin:/dist/boot/bin/:$PATH
ENV           NPM_CONFIG_PREFIX=/tmp/.npm-global

WORKDIR       /source/utils/config-gen
#RUN           npm install
RUN           yarn install
RUN           yarn build
RUN           mkdir -p /dist/boot/bin
RUN           mv "$GOPATH/src/$GIT_REPO/utils/config-gen/build" /dist/boot/bin/configurator

# XXX to start:
# ./node_modules/.bin/react-app-rewired start

#######################
# Builder assembly
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS builder-assembly-server

COPY          --from=builder-main   /dist/boot /dist/boot

COPY          --from=builder-tools  /boot/bin/goello-server-ng  /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/caddy          /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health    /dist/boot/bin

RUN           setcap 'cap_net_bind_service+ep' /dist/boot/bin/caddy

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Builder assembly
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS builder-assembly-config

COPY          --from=builder-main-config /dist/boot           /dist/boot

COPY          --from=builder-tools  /boot/bin/goello-server-ng   /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/caddy           /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health     /dist/boot/bin

RUN           setcap 'cap_net_bind_service+ep' /dist/boot/bin/caddy

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
ENV           TLS_MODE="internal"
# 1.2 or 1.3
ENV           TLS_MIN=1.2

# Either require_and_verify or verify_if_given
ENV           MTLS_ENABLED=true
ENV           MTLS_MODE="verify_if_given"
ENV           MTLS_TRUST="/certs/pki/authorities/local/root.crt"
ENV           PROXY=""

# Realm in case access is authenticated
ENV           REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           USERNAME=""
ENV           PASSWORD=""

# Log level and port
ENV           LOG_LEVEL=warn
ENV           PORT=443

ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
