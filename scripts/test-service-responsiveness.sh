#!/bin/bash
# The service's main thread stays responsive while a very long session streams: each save's
# main-thread time, and how fast the phone's and the Mac's list requests are answered meanwhile.
# BENCH_ROWS (20000), BENCH_SECONDS (8); BENCH_ENFORCE=0 only reports.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/source-list.sh
task_dir=$(mktemp -d /tmp/chatterbox-test-responsiveness.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_HOST_NOTIFY=0 CHATTERBOX_COMPANION_PORT=19661
export CHATTERBOX_PREFERENCES_SUITE="chatterbox.responsiveness.$(basename "$task_dir")"
export BENCH_ENFORCE="${BENCH_ENFORCE:-1}"
trap 'defaults delete "$CHATTERBOX_PREFERENCES_SUITE" >/dev/null 2>&1 || true; echo "Responsiveness artifacts: $task_dir"' EXIT
mkdir -p "$CHATTERBOX_DATA_DIR" build/DerivedData/Build/Products/Debug
defaults write "$CHATTERBOX_PREFERENCES_SUITE" companionEnabled -bool true
# The service's own sources, with the benchmark in place of its main.swift.
./scripts/runtime-sources.sh > "$task_dir/sources"
printf '%s\n' ChatterboxRuntime/RuntimeClient.swift \
 Chatterbox/Engine/CompanionServer.swift Chatterbox/Engine/ConnectorServer.swift Chatterbox/Engine/ConnectorTools.swift Chatterbox/Engine/DeskStore.swift Chatterbox/Engine/ProjectIssues.swift Chatterbox/Engine/CompanionDocuments.swift Chatterbox/Engine/ProxyQuota.swift \
 Chatterbox/Engine/CompanionMutationLedger.swift Chatterbox/Engine/NextSteps.swift \
 Chatterbox/Engine/MobilePush.swift Chatterbox/Engine/Pins.swift \
 Chatterbox/Support/HTTPFileTransfer.swift Shared/CompanionRetry.swift Shared/PlaceSuggestion.swift >> "$task_dir/sources"
find -L ChatterboxDaemon -name '*.swift' ! -name main.swift >> "$task_dir/sources"
check_source_list "$task_dir/sources"
cp tests/service-responsiveness/main.swift "$task_dir/main.swift"
# Optimized, as the installed service is.
swiftc -D CHATTERBOX_HEADLESS -whole-module-optimization -O \
  -o build/DerivedData/Build/Products/Debug/service-responsiveness @"$task_dir/sources" "$task_dir/main.swift"
build/DerivedData/Build/Products/Debug/service-responsiveness 2>"$task_dir/service.log"
