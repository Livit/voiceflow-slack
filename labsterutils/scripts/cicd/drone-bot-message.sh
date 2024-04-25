#!/usr/bin/env bash

set -e

VERSION=$($(dirname $0)/semver.sh)

STAGE=$1

DRONE_STATUS=${2:-"build"}

if [ -z "$DRONE_COMMIT_AUTHOR" ]; then
    echo "DRONE_COMMIT_AUTHOR is empty"
    exit
fi
if [ -n "$DRONE_BRANCH" ]; then
    INFO_BRANCH="Git branch \`${DRONE_BRANCH}\`. "
else
    INFO_BRANCH=""
fi
if [ -n "$DRONE_TAG" ]; then
    INFO_TAG="Git tag \`${DRONE_TAG}\`. "
else
    INFO_TAG=""
fi

INFO="App \`${DRONE_REPO_NAME}\`, version \`${VERSION}\`. ${INFO_BRANCH}${INFO_TAG}<${DRONE_BUILD_LINK}|Build link>."

if [ "$DRONE_STATUS" = "build" ]; then
    STATUS=${DRONE_BUILD_STATUS}
else
    STATUS=${DRONE_STAGE_STATUS}
fi

if [ "$STATUS" = "success" ]; then
    MESSAGE="${STAGE} finished :amongus-green: ${INFO}"
else
    MESSAGE="${STAGE} failed :amongus-red: ${INFO}"
fi

echo ${MESSAGE}

MESSAGE64=$(echo ${MESSAGE} | base64 -w0)

curl -d "token=${ANSIBLE_TOKEN}" --data-urlencode "text=slack ${DRONE_COMMIT_AUTHOR} ${MESSAGE64}" -X POST $ANSIBLE_URL
