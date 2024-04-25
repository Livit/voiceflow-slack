#!/usr/bin/env bash

set -e

PROJECT=$1
DOCKER_TAG_PREFIX=$2
HELM_CHART_PATH=${3:-".helm"}
ECR_REGION=${ECR_REGION:-"$AWS_DEFAULT_REGION"}

VERSION=$($(dirname $0)/semver.sh)
DOCKER_TAG=$($(dirname $0)/docker-tag.sh ${DOCKER_TAG_PREFIX})

echo $VERSION

if [ -z "$ECR_REPO" ]; then
  REPO=${PROJECT}
else
  REPO=${ECR_REPO}
fi

cat <<EOF >> ${HELM_CHART_PATH}/${PROJECT}/values.yaml
image:
  repository: ${AWS_ACCOUNT_ID}.dkr.ecr.${ECR_REGION}.amazonaws.com/${REPO}
  tag: ${DOCKER_TAG}
  pullPolicy: Always
EOF


cat <<EOF >> ${HELM_CHART_PATH}/$PROJECT/Chart.yaml
version: ${VERSION}
appVersion: ${VERSION}
EOF
