#!/bin/sh
# Runs the tests in Docker: ./tests/run.sh (exit status 0 = all passed).
# Plain Lua 5.1 (the pure Lua parts only, no C libraries), no network
# access needed at test time.
set -eu
cd "$(dirname "$0")/.."
image=debian:trixie@sha256:9c6e381421d0f48d1b8133e573f33c185ee16cbf505eda9c4a8a4791b25ea8a6
docker run --rm -e DEBIAN_FRONTEND=noninteractive -v "$PWD:/src:ro" -w /src "$image" sh -c '
  apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends lua5.1 >/dev/null
  status=0
  for test in tests/*-test.lua; do
    echo "== $test"
    lua5.1 "$test" </dev/null || status=1
  done
  exit "$status"'
