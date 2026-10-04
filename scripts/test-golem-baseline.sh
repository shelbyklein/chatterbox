#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/golem-baseline.XXXXXX)
trap 'rm -rf "$task_dir"' EXIT
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0
export BASELINE_RIG="$PWD/Golem/rig" BASELINE_REVISION="$(git rev-parse HEAD)"
export BASELINE_OUTPUT="$PWD/tests/golem-integration/artifacts/baseline.json"
products=build/DerivedData/Build/Products/Debug
rg --files Chatterbox ChatterboxRuntime Shared -g '*.swift' -g '!ChatterboxApp.swift' > "$task_dir/sources"
cp tests/golem-integration/baseline.swift "$task_dir/main.swift"
swiftc -I "$products" "$products/SwiftTerm.o" -D DEBUG -D GOLEM_APP -whole-module-optimization -O \
  -o "$task_dir/baseline" @"$task_dir/sources" "$task_dir/main.swift"
"$task_dir/baseline"
