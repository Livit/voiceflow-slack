#!/usr/bin/env bash

SEMVER_TAG_REGEX="^[vV]?(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"

HASH=$(git rev-parse --short HEAD)

if [ -n "$DRONE_TAG" ]; then
  TAG=${DRONE_TAG}
  rc=0
else
  TAG=$(git describe --exact-match --tags $(git log -n1 --pretty='%h') 2> /dev/null)
  rc=$?
fi

# monorepo support
if [ -n "$MONOREPO" ]; then
  TAG=$(echo ${TAG} | sed 's/.*-//')
fi

if [[ $rc == 0 ]] && [[ $TAG =~ $SEMVER_TAG_REGEX ]]; then
  DESCRIBE="$TAG"
else
  DESCRIBE="$HASH"
fi

if [ -n "$DRONE_BUILD_NUMBER" ]; then
  BUILD=${DRONE_BUILD_NUMBER}
else
  BUILD=$(git rev-list HEAD --count)
fi

if [ "${BUILD}" = "" ]; then
    BUILD='0'
fi

if [[ "${DESCRIBE}" =~ ^[A-Fa-f0-9]+$ ]]; then
    VERSION="0.0.0-build.${BUILD}.x${HASH}"
else
    VERSION="${DESCRIBE}"
fi

echo "$VERSION"
