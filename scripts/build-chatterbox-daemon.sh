#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/source-list.sh
source scripts/lib/build-lock.sh
mkdir -p build/runtime
manifest=$(mktemp /tmp/chatterbox-test-daemon-sources.XXXXXX)
trap 'rm -f "$manifest"' EXIT
./scripts/runtime-sources.sh > "$manifest"
printf '%s\n' ChatterboxRuntime/RuntimeClient.swift >> "$manifest"
printf '%s\n' \
 Chatterbox/Engine/CompanionServer.swift Chatterbox/Engine/ConnectorServer.swift Chatterbox/Engine/ConnectorTools.swift Chatterbox/Engine/DeskStore.swift Chatterbox/Engine/ProjectIssues.swift Chatterbox/Engine/CompanionDocuments.swift Chatterbox/Engine/ProxyQuota.swift \
 Chatterbox/Engine/CompanionMutationLedger.swift Chatterbox/Engine/NextSteps.swift \
 Chatterbox/Engine/MobilePush.swift Chatterbox/Engine/Pins.swift \
 Chatterbox/Support/HTTPFileTransfer.swift Shared/CompanionRetry.swift Shared/PlaceSuggestion.swift >> "$manifest"
find -L ChatterboxDaemon -name '*.swift' >> "$manifest"
check_source_list "$manifest"
swiftc -D DEBUG -D CHATTERBOX_HEADLESS -whole-module-optimization -Onone -o build/runtime/chatterboxd @"$manifest"
