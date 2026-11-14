#!/bin/sh
set -eu
image=$1
output=$2
engine=${CONTAINER_ENGINE:-docker}
mkdir -p "$output"
"$engine" image inspect --format '{{.Id}} {{.Architecture}} {{.Os}}' "$image" >"$output/image.txt"
"$engine" run --rm --entrypoint cat "$image" /opt/vellum/aio/versions.env >"$output/versions.env"
"$engine" run --rm --entrypoint dpkg-query "$image" -W >"$output/os-packages.tsv"
"$engine" run --rm --entrypoint cat "$image" /opt/vellum/bun.lock >"$output/bun.lock"
# Syft scans a Docker archive so it works with either local engine.
archive=$(mktemp "$output/image.XXXXXXXX.tar")
trap 'rm -f "$archive"' EXIT HUP INT TERM
if [ "${engine##*/}" = podman ]; then
    set -- --format docker-archive
else
    set --
fi
"$engine" save "$@" "$image" >"$archive"
"$engine" run --rm -v "$(realpath "$archive"):/input/image.tar:ro,Z" \
    docker.io/anchore/syft:v1.27.1@sha256:844ed6a928ef9396fac26d1de374e71dcaf80df14f05841670ed41619c5a718f \
    scan docker-archive:/input/image.tar -o spdx-json >"$output/vellum-aio.spdx.json"
