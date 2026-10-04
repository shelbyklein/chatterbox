#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/golem-runtime.XXXXXX)
trap 'echo "Runtime test artifacts: $task_dir"' EXIT
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_HOST_BINARY="$PWD/build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/MacOS/ChatterboxHost"
export CHATTERBOX_HOST_NOTIFY=0 CHATTERBOX_HOST_IDLE_SECONDS=1 CHATTERBOX_HOST_DETACHED_IDLE_SECONDS=1
export FAKE_PROVIDER="$PWD/tests/golem-integration/fake-provider.py"
mkdir -p "$CHATTERBOX_DATA_DIR"
./scripts/runtime-sources.sh > "$task_dir/sources"
cp tests/golem-integration/core.swift "$task_dir/main.swift"
swiftc -D CHATTERBOX_HEADLESS -whole-module-optimization -Onone \
  -o "$task_dir/core" @"$task_dir/sources" "$task_dir/main.swift"
"$task_dir/core"
