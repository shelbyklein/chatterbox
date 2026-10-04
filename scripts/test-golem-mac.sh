#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/golem-mac.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_PREFERENCES_SUITE="com.shelbyklein.golem.fixture.${task_dir##*/}"
export CHATTERBOX_DAEMON_CLIENT=1 CHATTERBOX_TEST_TRUST_UI=1 CHATTERBOX_TEST_DISABLE_COMPUTER=1
export CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0
export FAKE_PROVIDER="$PWD/tests/golem-integration/fake-provider.py"
export CHATTERBOX_HOST_BINARY="$PWD/build/GolemPlan/Build/Products/Debug/Chatterbox.app/Contents/MacOS/ChatterboxHost"
export CHATTERBOX_HOST_NOTIFY=0 CHATTERBOX_HOST_IDLE_SECONDS=1 CHATTERBOX_HOST_DETACHED_IDLE_SECONDS=1
export GOLEM_TEST_JOB=fixture-native-capture
export GOLEM_TEST_CAPTURE="$PWD/tests/golem-integration/artifacts"
mkdir -p "$CHATTERBOX_DATA_DIR/Dot/Avatar"
cp -R "${GOLEM_REPO:-../Golem}/Golem/rig/." "$CHATTERBOX_DATA_DIR/Dot/Avatar/"
build/runtime/chatterboxd > "$task_dir/daemon.log" 2>&1 &
daemon_pid=$!
build/runtime/golemd > "$task_dir/service.log" 2>&1 &
service_pid=$!
trap 'kill "$service_pid" "$daemon_pid" 2>/dev/null || true; echo "Native Golem artifacts: $task_dir"' EXIT
"${GOLEM_REPO:-../Golem}/build/GolemPlan/Build/Products/Debug/Golem.app/Contents/MacOS/Golem" -ApplePersistenceIgnoreState YES > "$task_dir/app.log" 2>&1
