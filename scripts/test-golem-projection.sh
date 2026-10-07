#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
golem_root=$(cd "${GOLEM_REPO:-../Golem}" && pwd)
task_dir=$(mktemp -d /tmp/golem-projection.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_DAEMON_CLIENT=1 CHATTERBOX_TEST_TRUST_UI=1 CHATTERBOX_TEST_DISABLE_COMPUTER=1
export CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0
export FAKE_PROVIDER="$PWD/tests/golem-integration/fake-provider.py"
export CHATTERBOX_HOST_BINARY="$PWD/build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/MacOS/ChatterboxHost"
export CHATTERBOX_HOST_NOTIFY=0 CHATTERBOX_HOST_IDLE_SECONDS=1 CHATTERBOX_HOST_DETACHED_IDLE_SECONDS=1
export PROJECTION_CAPTURE="$PWD/tests/golem-integration/artifacts/projection.png"
export GOLEM_TEST_APP_PATH="${golem_root}/build/GolemPlan/Build/Products/Debug/Golem.app"
export GOLEM_TEST_CAPTURE="$PWD/tests/golem-integration/artifacts"
products=build/DerivedData/Build/Products/Debug
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$task_dir/sources"
cp tests/golem-integration/projection.swift "$task_dir/main.swift"
swiftc -I "$products" "$products/SwiftTerm.o" -D DEBUG -whole-module-optimization -Onone -o "$task_dir/projection" @"$task_dir/sources" "$task_dir/main.swift"
build/runtime/chatterboxd > "$task_dir/daemon.log" 2>&1 &
daemon_pid=$!
mkdir -p "$CHATTERBOX_DATA_DIR/Dot/Avatar"
cp -R "${golem_root}/Golem/rig/." "$CHATTERBOX_DATA_DIR/Dot/Avatar/"
export GOLEM_TEST_DISABLE_AUTOMATION=1
build/runtime/golemd > "$task_dir/service.log" 2>&1 &
service_pid=$!
trap 'kill "$service_pid" "$daemon_pid" 2>/dev/null || true; echo "Projection artifacts: $task_dir"' EXIT
"$task_dir/projection"
