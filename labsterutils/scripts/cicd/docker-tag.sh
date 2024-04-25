#!/usr/bin/env bash

set -e

DOCKER_TAG_PREFIX=$1

VERSION=$($(dirname $0)/semver.sh)
DOCKER_TAG=$(echo ${VERSION} | tr '+' '_')

if [ -n "$DOCKER_TAG_PREFIX" ]; then
  DOCKER_TAG="${DOCKER_TAG_PREFIX}-${DOCKER_TAG}"
fi

echo ${DOCKER_TAG}
