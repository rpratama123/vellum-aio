#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./versions.env
printf '%s\n' "$VELLUM_SHA" | grep -Eq '^[a-f0-9]{40}$'
printf '%s\n' "$BUN_LOCK_SHA" | grep -Eq '^[a-f0-9]{64}$'
grep -Fq "upstream-revision=\"$VELLUM_SHA\"" Dockerfile
grep -Fq "oven/bun:$BUN_VERSION@" Dockerfile
awk '
    /^FROM / && $2 != "base" {
        if (!match($2, /@sha256:[a-f0-9]+$/) || RLENGTH != 72) exit 1
    }
' Dockerfile
