#!/usr/bin/env bash
# $1 - host
# $2 - port
WAIT=${3:-120}
for i in $(seq 1 $WAIT); do
  echo "Waiting for $1:$2 ($i sec)"
  sleep 1
  if nc -z $1 $2; then
    exit 0
  fi
done
exit 1
