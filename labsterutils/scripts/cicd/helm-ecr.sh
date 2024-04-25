#!/usr/bin/env bash

set -e

PROJECT=$1
HELM_CHART_FILE=$2

aws ecr get-login-password \
     --region ${AWS_DEFAULT_REGION} | helm registry login \
     --username AWS \
     --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com

if [ -z "$HELM_CHART_FILE" ]; then
  HELM_OUTPUT=$(helm package ./.helm/${PROJECT} -d /tmp)
  HELM_CHART_FILE=$(echo $HELM_OUTPUT | sed 's/.*: //')
fi

helm push $HELM_CHART_FILE oci://${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/

echo Pushed ${HELM_CHART_FILE} to oci://${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/
