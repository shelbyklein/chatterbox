#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/chatterbox-render.XXXXXX)
trap 'echo "Regression artifacts: $test_dir"' EXIT
export CHATTERBOX_DATA_DIR="$test_dir/data"
export CHATTERBOX_HOST_DIR="$test_dir/host"
export CHATTERBOX_AGENT_PORT=0
export CHATTERBOX_COMPANION_PORT=0
mkdir -p "$CHATTERBOX_DATA_DIR"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name 'ChatterboxApp.swift' > "$test_dir/files.txt"
swiftc -I build/DerivedData/Build/Products/Debug build/DerivedData/Build/Products/Debug/SwiftTerm.o -D DEBUG -whole-module-optimization -Onone -o "$test_dir/test" \
  @"$test_dir/files.txt" tests/chat-rendering/main.swift
"$test_dir/test"
