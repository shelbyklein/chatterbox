#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$(mktemp -d /tmp/golem-animation-performance.XXXXXX)
export CHATTERBOX_DATA_DIR="$root/data" CHATTERBOX_HOST_DIR="$root/host"
export CHATTERBOX_PREFERENCES_SUITE="com.shelbyklein.fixture.${root##*/}"
export CHATTERBOX_DAEMON_CLIENT=1 CHATTERBOX_TEST_TRUST_UI=1 CHATTERBOX_TEST_DISABLE_COMPUTER=1
export CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0 GOLEM_TEST_DISABLE_AUTOMATION=1
export GOLEM_TEST_PERFORMANCE="$PWD/tests/golem-integration/artifacts/${GOLEM_PERF_OUTPUT:-golem-animation-performance.json}"
mkdir -p "$CHATTERBOX_DATA_DIR/Dot/Avatar"
cp -R "${GOLEM_REPO:-../Golem}/Golem/rig/." "$CHATTERBOX_DATA_DIR/Dot/Avatar/"
build/runtime/chatterboxd > "$root/daemon.log" 2>&1 &
daemon_pid=$!
build/runtime/golemd > "$root/service.log" 2>&1 &
service_pid=$!
trap 'kill "$service_pid" "$daemon_pid" 2>/dev/null || true; echo "Animation performance artifacts: $root"' EXIT
python3 tests/golem-integration/service-performance.py "$daemon_pid" "$service_pid" "$GOLEM_TEST_PERFORMANCE.services.json" > "$root/sampler.log" 2>&1 &
sampler_pid=$!
trap 'kill "$sampler_pid" "$service_pid" "$daemon_pid" 2>/dev/null || true; echo "Animation performance artifacts: $root"' EXIT
"${GOLEM_PERF_APP:-${GOLEM_REPO:-../Golem}/build/GolemPlan/Build/Products/Debug/Golem.app/Contents/MacOS/Golem}" -ApplePersistenceIgnoreState YES > "$root/app.log" 2>&1
