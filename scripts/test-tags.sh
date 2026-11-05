#!/bin/bash
# Tags on the Mac in daemon mode (tests/tags): toggleTag reaches the service, survives its
# updates and a full list refresh, shows in allTags and redraws the sidebar; the service saves it.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/chatterbox-test-tags.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_DAEMON_CLIENT=1 CHATTERBOX_TEST_TRUST_UI=1 CHATTERBOX_TEST_DISABLE_COMPUTER=1
export CHATTERBOX_PREFERENCES_SUITE="com.shelbyklein.Chatterbox.tags-test.$RANDOM.$$"
export CHATTERBOX_COMPANION_PORT=0 CHATTERBOX_HOST_NOTIFY=0
export CHATTERBOX_HOST_BINARY="$PWD/build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/Helpers/ChatterboxHost.app/Contents/MacOS/ChatterboxHost"
products=build/DerivedData/Build/Products/Debug
[[ -f "$products/SwiftTerm.o" ]] || { echo "Build first: xcodebuild -scheme Chatterbox -derivedDataPath build/DerivedData build" >&2; exit 1; }
[[ -x build/runtime/chatterboxd ]] || scripts/build-chatterbox-daemon.sh
mkdir -p "$CHATTERBOX_DATA_DIR"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$task_dir/sources"
swiftc -I "$products" "$products/SwiftTerm.o" -D DEBUG -whole-module-optimization -Onone \
  -o "$products/tags-tests" @"$task_dir/sources" tests/tags/main.swift
trap 'echo "Tags artifacts: $task_dir"; defaults delete "$CHATTERBOX_PREFERENCES_SUITE" >/dev/null 2>&1 || true' EXIT
"$products/tags-tests" seed
build/runtime/chatterboxd > "$task_dir/daemon.log" 2>&1 &
for attempt in {1..100}; do
  [[ -S "$CHATTERBOX_DATA_DIR/daemon.sock" ]] && break
  sleep 0.1
done
"$products/tags-tests"
