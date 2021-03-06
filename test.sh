#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

TEST_DOES_NOT_BUILD=${TEST_DOES_NOT_BUILD:-}

if ! hadolint ./*Dockerfile*; then
  >&2 printf "Failed linting on Dockerfile\n"
  exit 1
fi

if ! shellcheck ./*.sh; then
  >&2 printf "Failed shellchecking\n"
  exit 1
fi

if [ ! "$TEST_DOES_NOT_BUILD" ]; then
  [ ! -e "./refresh.sh" ] || ./refresh.sh
  if ! ./hack/cue-bake server --inject platforms=linux/arm64; then
    >&2 printf "Failed building server\n"
    exit 1
  fi
  if ! ./hack/cue-bake config --inject platforms=linux/arm64; then
    >&2 printf "Failed building config\n"
    exit 1
  fi
fi
