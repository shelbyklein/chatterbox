#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/golem-performance.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host" CHATTERBOX_PREFERENCES_SUITE="com.shelbyklein.golem.perf.${task_dir##*/}"
export CHATTERBOX_DAEMON_CLIENT=1 CHATTERBOX_TEST_TRUST_UI=1 CHATTERBOX_TEST_DISABLE_COMPUTER=1
export CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0 GOLEM_TEST_DISABLE_AUTOMATION=1
export FAKE_PROVIDER="$PWD/tests/golem-integration/fake-provider.py"
export BASELINE_REVISION="$(git rev-parse HEAD)" BASELINE_OUTPUT="$PWD/tests/golem-integration/artifacts/performance.json"
export PERF_DAEMON="$PWD/build/runtime/chatterboxd" PERF_SERVICE="$PWD/build/runtime/golemd"
products=build/GolemPlan/Build/Products/Debug
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name 'ChatterboxApp.swift' > "$task_dir/sources"
cp tests/golem-integration/performance.swift "$task_dir/main.swift"
swiftc -I "$products" "$products/SwiftTerm.o" -D DEBUG -whole-module-optimization -O -o "$task_dir/performance" @"$task_dir/sources" "$task_dir/main.swift"
"$task_dir/performance"
echo "Performance artifacts: $task_dir"
