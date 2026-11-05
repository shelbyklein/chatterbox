#!/bin/bash
# Work threads (plans/work-threads.md), as the service runs them: built like chatterboxd
# (CHATTERBOX_HEADLESS) with the service socket, the Desk and the phone's routes, and real turns
# through the fixture providers in ChatterboxHost (build the Mac app first: build/DerivedData).
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/source-list.sh
task_dir=$(mktemp -d /tmp/chatterbox-test-work.XXXXXX)
trap 'echo "Work threads test artifacts: $task_dir"' EXIT
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_HOST_BINARY="$PWD/build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/Helpers/ChatterboxHost.app/Contents/MacOS/ChatterboxHost"
export CHATTERBOX_HOST_NOTIFY=0 CHATTERBOX_HOST_IDLE_SECONDS=1 CHATTERBOX_HOST_DETACHED_IDLE_SECONDS=1
export FAKE_PROVIDER="$PWD/tests/fixtures/fake-provider.py" FAKE_PROVIDER_WAKE_SECONDS=0.3
export CHATTERBOX_PREFERENCES_SUITE="chatterbox.work.$(basename "$task_dir")" CHATTERBOX_COMPANION_PORT=0 CHATTERBOX_CONNECTOR_PORT=0 CHATTERBOX_TEST_TRUST_UI=1
[[ -x "$CHATTERBOX_HOST_BINARY" ]] || { echo "No ChatterboxHost at $CHATTERBOX_HOST_BINARY: build the Mac app first." >&2; exit 1; }
mkdir -p "$CHATTERBOX_DATA_DIR"
./scripts/runtime-sources.sh > "$task_dir/sources"
printf '%s\n' ChatterboxRuntime/RuntimeClient.swift \
 Chatterbox/Engine/CompanionServer.swift Chatterbox/Engine/ConnectorServer.swift Chatterbox/Engine/ConnectorTools.swift Chatterbox/Engine/DeskStore.swift \
 Chatterbox/Engine/CompanionDocuments.swift Chatterbox/Engine/ProxyQuota.swift Chatterbox/Engine/CompanionMutationLedger.swift Chatterbox/Engine/NextSteps.swift \
 Chatterbox/Engine/MobilePush.swift Chatterbox/Engine/Pins.swift Chatterbox/Support/HTTPFileTransfer.swift \
 Shared/CompanionRetry.swift Shared/PlaceSuggestion.swift >> "$task_dir/sources"
# The service's own files, but its main.swift: the test is the program.
find -L ChatterboxDaemon -name '*.swift' ! -name main.swift >> "$task_dir/sources"
check_source_list "$task_dir/sources"
swiftc -D DEBUG -D CHATTERBOX_HEADLESS -whole-module-optimization -Onone -o "$task_dir/test" @"$task_dir/sources" tests/work-threads/main.swift
"$task_dir/test"
