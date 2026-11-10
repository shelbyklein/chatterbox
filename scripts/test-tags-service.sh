#!/bin/bash
# Tags in the service (tests/tags-service): the Mac's metadata op sets them, and they show at
# once in the socket's list and the phone's /v1/chats (both cached by revision) and on disk.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/source-list.sh
task_dir=$(mktemp -d /tmp/chatterbox-test-tags-service.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_HOST_NOTIFY=0 CHATTERBOX_COMPANION_PORT=19662 CHATTERBOX_TEST_TRUST_UI=1
export CHATTERBOX_PREFERENCES_SUITE="chatterbox.tags-service.$(basename "$task_dir")"
trap 'defaults delete "$CHATTERBOX_PREFERENCES_SUITE" >/dev/null 2>&1 || true; echo "Tags service artifacts: $task_dir"' EXIT
mkdir -p "$CHATTERBOX_DATA_DIR" build/DerivedData/Build/Products/Debug
defaults write "$CHATTERBOX_PREFERENCES_SUITE" companionEnabled -bool true
# The service's own sources, with the test in place of its main.swift.
./scripts/runtime-sources.sh > "$task_dir/sources"
printf '%s\n' ChatterboxRuntime/RuntimeClient.swift \
 Chatterbox/Engine/CompanionServer.swift Chatterbox/Engine/ConnectorServer.swift Chatterbox/Engine/ConnectorTools.swift Chatterbox/Engine/DeskStore.swift Chatterbox/Engine/ProjectIssues.swift Chatterbox/Engine/CompanionDocuments.swift Chatterbox/Engine/ProxyQuota.swift \
 Chatterbox/Engine/CompanionMutationLedger.swift Chatterbox/Engine/NextSteps.swift \
 Chatterbox/Engine/MobilePush.swift Chatterbox/Engine/Pins.swift \
 Chatterbox/Support/HTTPFileTransfer.swift Shared/CompanionRetry.swift Shared/PlaceSuggestion.swift >> "$task_dir/sources"
find -L ChatterboxDaemon -name '*.swift' ! -name main.swift >> "$task_dir/sources"
check_source_list "$task_dir/sources"
swiftc -D DEBUG -D CHATTERBOX_HEADLESS -whole-module-optimization -Onone \
  -o build/DerivedData/Build/Products/Debug/tags-service-tests @"$task_dir/sources" tests/tags-service/main.swift
build/DerivedData/Build/Products/Debug/tags-service-tests 2>"$task_dir/service.log"
