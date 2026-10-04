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
rg --files Chatterbox ChatterboxRuntime Shared -g '*.swift' -g '!ChatterboxApp.swift' > "$test_dir/files.txt"
# Cache the unchanged engine, so iterating on native-event fixtures does not recompile the app.
engine_key=$({ swiftc --version; cat "$test_dir/files.txt"; while IFS= read -r source; do cat "$source"; done < "$test_dir/files.txt"; } | shasum -a 256 | cut -c 1-16)
engine_dir="/tmp/chatterbox-mini-engine.$engine_key"
if [[ ! -f "$engine_dir/libChatterboxTestEngine.dylib" || ! -f "$engine_dir/ChatterboxTestEngine.swiftmodule" ]]; then
  mkdir -p "$engine_dir"
  swiftc -I build/GolemPlan/Build/Products/Debug build/GolemPlan/Build/Products/Debug/SwiftTerm.o -D DEBUG -D GOLEM_APP -whole-module-optimization -Onone -enable-testing \
    -emit-library -emit-module -module-name ChatterboxTestEngine \
    -emit-module-path "$engine_dir/ChatterboxTestEngine.swiftmodule" \
    -o "$engine_dir/libChatterboxTestEngine.dylib" @"$test_dir/files.txt"
fi
swiftc -I build/GolemPlan/Build/Products/Debug -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine \
  -Xlinker -rpath -Xlinker "$engine_dir" -o "$test_dir/GolemMiniRegression" tests/golem-mini/main.swift
"$test_dir/GolemMiniRegression"
