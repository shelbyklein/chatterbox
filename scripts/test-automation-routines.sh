#!/bin/bash
# Automations from the phone, as the service runs them: built like chatterboxd
# (CHATTERBOX_HEADLESS), with a stand-in for each run's session, so no agent ever starts.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/source-list.sh
fixture=$(mktemp -d /tmp/chatterbox-test-automation-routines.XXXXXX)
trap 'echo "Automation routines test artifacts: $fixture"' EXIT
./scripts/runtime-sources.sh > "$fixture/sources"
printf '%s\n' ChatterboxRuntime/RuntimeClient.swift \
 Chatterbox/Engine/CompanionServer.swift Chatterbox/Engine/ConnectorServer.swift Chatterbox/Engine/ConnectorTools.swift Chatterbox/Engine/DeskStore.swift \
 Chatterbox/Engine/CompanionDocuments.swift Chatterbox/Engine/ProxyQuota.swift Chatterbox/Engine/CompanionMutationLedger.swift Chatterbox/Engine/NextSteps.swift \
 Chatterbox/Engine/MobilePush.swift Chatterbox/Engine/Pins.swift Chatterbox/Support/HTTPFileTransfer.swift \
 Shared/CompanionRetry.swift Shared/PlaceSuggestion.swift >> "$fixture/sources"
# The service's own files, but its main.swift: the test is the program.
find -L ChatterboxDaemon -name '*.swift' ! -name main.swift >> "$fixture/sources"
check_source_list "$fixture/sources"
swiftc -D DEBUG -D CHATTERBOX_HEADLESS -whole-module-optimization -Onone -o "$fixture/test" @"$fixture/sources" tests/automation-routines/main.swift
mkdir -p "$fixture/data"
CHATTERBOX_DATA_DIR="$fixture/data" CHATTERBOX_HOST_DIR="$fixture/host" CHATTERBOX_PREFERENCES_SUITE="chatterbox.automations.$(basename "$fixture")" \
 CHATTERBOX_COMPANION_PORT=0 CHATTERBOX_CONNECTOR_PORT=0 CHATTERBOX_TEST_TRUST_UI=1 "$fixture/test"
