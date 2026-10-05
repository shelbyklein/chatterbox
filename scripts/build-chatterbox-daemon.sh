#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/runtime
manifest=$(mktemp /tmp/golem-daemon-sources.XXXXXX)
trap 'rm -f "$manifest"' EXIT
./scripts/runtime-sources.sh > "$manifest"
printf '%s\n' ChatterboxRuntime/RuntimeClient.swift >> "$manifest"
printf '%s\n' \
 Chatterbox/Engine/CompanionServer.swift Chatterbox/Engine/CompanionDocuments.swift \
 Chatterbox/Engine/CompanionMutationLedger.swift Chatterbox/Engine/NextSteps.swift \
 Chatterbox/Engine/MobilePush.swift Chatterbox/Engine/Pins.swift Chatterbox/Engine/ProjectAutomations.swift \
 Chatterbox/Support/HTTPFileTransfer.swift Shared/CompanionAPI.swift Shared/CompanionRetry.swift >> "$manifest"
find -L ChatterboxDaemon -name '*.swift' >> "$manifest"
swiftc -D DEBUG -D CHATTERBOX_HEADLESS -whole-module-optimization -Onone -o build/runtime/chatterboxd @"$manifest"
