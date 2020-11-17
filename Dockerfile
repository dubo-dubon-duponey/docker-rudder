ARG           BUILDER_BASE=dubodubonduponey/base:builder
ARG           RUNTIME_BASE=dubodubonduponey/base:runtime

#######################
# Extra builder for healthchecker
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/http-health ./cmd/http

#######################
# Goello
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-goello

ARG           GIT_REPO=github.com/dubo-dubon-duponey/goello
ARG           GIT_VERSION=6f6c96ef8161467ab25be45fe3633a093411fcf2

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/goello-server ./cmd/server/main.go

#######################
# Caddy
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-caddy

# This is 2.2.1 (11/16/2020)
ARG           GIT_REPO=github.com/caddyserver/caddy
ARG           GIT_VERSION=385adf5d878939c381c7f73c771771d34523a1a7

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone https://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/caddy ./cmd/caddy

#######################
# Rudder server:
# https://github.com/rudderlabs/rudder-server/wiki/RudderStack-Telemetry
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-main-rudder

# October 1st, 2020
#ARG           GIT_VERSION=1d34d04e6b2ac6ae026f349f5504712acb3e891b
# November 5, 2020
ARG           GIT_REPO=github.com/rudderlabs/rudder-server
ARG           GIT_VERSION=6b0707ff7ab2c384adacdb7d59e8c7a6cbc77828

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           FLAGS=""; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w $FLAGS" \
                -o /dist/boot/bin/rudder ./main.go


#######################
# Config generator: https://github.com/rudderlabs/rudder-server/wiki/RudderStack-Config-Generator
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-main-config

# XXX node-gyp is bollocks
ENV           USER=root
RUN           mkdir -p /tmp/.npm-global
ENV           PATH=/tmp/.npm-global/bin:$PATH
ENV           NPM_CONFIG_PREFIX=/tmp/.npm-global

# October 1st, 2020
#ARG           GIT_VERSION=1d34d04e6b2ac6ae026f349f5504712acb3e891b
# November 5, 2020
ARG           GIT_REPO=github.com/rudderlabs/rudder-server
ARG           GIT_VERSION=6b0707ff7ab2c384adacdb7d59e8c7a6cbc77828

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
WORKDIR       $GOPATH/src/$GIT_REPO/utils/config-gen
RUN           npm install
RUN           yarn build
RUN           mkdir -p /dist/boot/bin
RUN           mv "$GOPATH/src/$GIT_REPO/utils/config-gen/build" /dist/boot/bin/configurator


# XXX to start:
# ./node_modules/.bin/react-app-rewired start

#######################
# Builder assembly
#######################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder-assembly-server

COPY          --from=builder-healthcheck  /dist/boot/bin /dist/boot/bin
# COPY          --from=builder-caddy        /dist/boot/bin /dist/boot/bin
COPY          --from=builder-goello       /dist/boot/bin /dist/boot/bin

COPY          --from=builder-main-rudder /dist/boot/bin /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot/bin -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Builder assembly
#######################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder-assembly-config

COPY          --from=builder-healthcheck  /dist/boot/bin /dist/boot/bin
COPY          --from=builder-caddy        /dist/boot/bin /dist/boot/bin
COPY          --from=builder-goello       /dist/boot/bin /dist/boot/bin

COPY          --from=builder-main-config  /dist/boot/bin /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot/bin -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image, server
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE                                                                                             AS server

COPY          --from=builder-assembly-server --chown=$BUILD_UID:root /dist .

EXPOSE        5000

# VOLUME        /data
VOLUME        /tmp

# mDNS
ENV           MDNS_NAME=""
ENV           MDNS_HOST="rudder-server"
ENV           MDNS_TYPE=_http._tcp

# Authentication
ENV           USERNAME="dubo-dubon-duponey"
ENV           PASSWORD="base64_bcrypt_encoded_use_caddy_hash_password_to_generate"
ENV           REALM="My precious rudder"

# Log level and port
ENV           LOG_LEVEL=info
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

ENV           HEALTHCHECK_URL=http://127.0.0.1:5000/

HEALTHCHECK   --interval=30s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1

#######################
# Running image, configurator
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE                                                                                             AS config

COPY          --from=builder-assembly-config --chown=$BUILD_UID:root /dist .

EXPOSE        3000

# mDNS
ENV           MDNS_NAME=""
ENV           MDNS_HOST="rudder-config"
ENV           MDNS_TYPE=_http._tcp

# Authentication
ENV           USERNAME="dubo-dubon-duponey"
ENV           PASSWORD="base64_bcrypt_encoded_use_caddy_hash_password_to_generate"
ENV           REALM="My precious rudder config"

# Log level and port
ENV           LOG_LEVEL=info
ENV           PORT=3000
ENV           INTERNAL_PORT=3000

ENV           HEALTHCHECK_URL=http://127.0.0.1:3000/

HEALTHCHECK   --interval=30s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1

