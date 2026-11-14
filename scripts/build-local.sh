#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./versions.env
engine=${CONTAINER_ENGINE:-docker}
image=${1:-vellum-aio:$VELLUM_VERSION}
if [ "$#" -gt 0 ]; then
    shift
fi
if [ "${engine##*/}" = podman ]; then
    set -- --format docker --layers "$@"
fi
"$engine" build "$@" --platform linux/amd64 -t "$image" .
"$engine" image inspect --format '{{.Id}}' "$image"
