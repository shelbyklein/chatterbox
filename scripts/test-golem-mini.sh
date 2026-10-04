#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/chatterbox-mini.XXXXXX)
trap 'echo "Mini window artifacts: $test_dir"' EXIT
export CHATTERBOX_DATA_DIR="$test_dir/data"
export CHATTERBOX_HOST_DIR="$test_dir/host"
export CHATTERBOX_AGENT_PORT=0
export CHATTERBOX_COMPANION_PORT=0
mkdir -p "$CHATTERBOX_DATA_DIR"
engine_dir=$(./scripts/build-golem-test-engine.sh)
swiftc -I build/GolemPlan/Build/Products/Debug -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine \
  -Xlinker -rpath -Xlinker "$engine_dir" -o "$test_dir/GolemMiniRegression" tests/golem-mini/main.swift
"$test_dir/GolemMiniRegression"
