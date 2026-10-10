#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/source-list.sh
fixture=$(mktemp -d /tmp/golem-promotion.XXXXXX)
trap 'echo "Promotion test artifacts: $fixture"' EXIT
./scripts/runtime-sources.sh > "$fixture/sources"
printf '%s\n' ChatterboxRuntime/RuntimeClient.swift Chatterbox/Engine/CompanionServer.swift Chatterbox/Engine/CompanionDocuments.swift Chatterbox/Engine/CompanionMutationLedger.swift Chatterbox/Engine/NextSteps.swift Chatterbox/Engine/MobilePush.swift Chatterbox/Engine/Pins.swift Chatterbox/Support/HTTPFileTransfer.swift Shared/CompanionRetry.swift ChatterboxDaemon/DaemonContext.swift >> "$fixture/sources"
check_source_list "$fixture/sources"
swiftc -D DEBUG -D CHATTERBOX_HEADLESS -whole-module-optimization -Onone -o "$fixture/test" @"$fixture/sources" tests/mobile-promotion/main.swift
CHATTERBOX_DATA_DIR="$fixture/data" CHATTERBOX_PREFERENCES_SUITE="chatterbox.promotion.$(basename "$fixture")" CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0 "$fixture/test"
