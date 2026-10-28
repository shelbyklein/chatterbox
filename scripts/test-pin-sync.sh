#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/source-list.sh
task_dir=$(mktemp -d /tmp/chatterbox-pin-sync.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_COMPANION_PORT=0
export CHATTERBOX_PREFERENCES_SUITE="chatterbox.pin-sync.$(basename "$task_dir")"
mkdir -p "$CHATTERBOX_DATA_DIR" build/DerivedData/Build/Products/Debug
./scripts/runtime-sources.sh > "$task_dir/sources"
printf '%s\n' ChatterboxDaemon/DaemonContext.swift >> "$task_dir/sources"
check_source_list "$task_dir/sources"
cp tests/pin-sync/main.swift "$task_dir/main.swift"
swiftc -D CHATTERBOX_HEADLESS -whole-module-optimization -Onone \
  -o build/DerivedData/Build/Products/Debug/pin-sync-tests @"$task_dir/sources" "$task_dir/main.swift"
build/DerivedData/Build/Products/Debug/pin-sync-tests
printf 'Secret test artifacts: %s\n' "$task_dir"
