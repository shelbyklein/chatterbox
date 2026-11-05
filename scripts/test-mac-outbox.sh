#!/bin/bash
# Changes made on the Mac can't be lost (tests/mac-outbox, plans/mac-outbox.md): the app in
# daemon mode talks to a real service through a proxy that drops, delays or refuses its
# requests; the service is killed and restarted mid-change; the app quits with changes pending
# and a new one sends them. Tags, a rename, the Brief, a setting, archive, delete and a new session
# all end up on the service; the service's old copy never reverts a pending change on the Mac;
# a late partial send doesn't undo the phone's rename.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/chatterbox-test-mac-outbox.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_DAEMON_CLIENT=1 CHATTERBOX_TEST_TRUST_UI=1 CHATTERBOX_TEST_DISABLE_COMPUTER=1
export CHATTERBOX_PREFERENCES_SUITE="com.shelbyklein.Chatterbox.outbox-test.$RANDOM.$$"
export CHATTERBOX_COMPANION_PORT=0 CHATTERBOX_HOST_NOTIFY=0
export CHATTERBOX_HOST_BINARY="$PWD/build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/Helpers/ChatterboxHost.app/Contents/MacOS/ChatterboxHost"
products=build/DerivedData/Build/Products/Debug
[[ -f "$products/SwiftTerm.o" ]] || { echo "Build first: xcodebuild -scheme Chatterbox -derivedDataPath build/DerivedData build" >&2; exit 1; }
[[ -x build/runtime/chatterboxd ]] || scripts/build-chatterbox-daemon.sh
mkdir -p "$CHATTERBOX_DATA_DIR"
# The test starts (and kills, and restarts) the service itself; a copy here is stopped with the run.
cp build/runtime/chatterboxd "$task_dir/chatterboxd"
export OUTBOX_DAEMON="$task_dir/chatterboxd" OUTBOX_LOGS="$task_dir"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$task_dir/sources"
swiftc -I "$products" "$products/SwiftTerm.o" -D DEBUG -whole-module-optimization -Onone \
  -o "$products/mac-outbox-tests" @"$task_dir/sources" tests/mac-outbox/main.swift
trap 'echo "Outbox artifacts: $task_dir"; defaults delete "$CHATTERBOX_PREFERENCES_SUITE" >/dev/null 2>&1 || true' EXIT
"$products/mac-outbox-tests" seed
"$products/mac-outbox-tests"
echo "--- relaunch"
"$products/mac-outbox-tests" relaunch
