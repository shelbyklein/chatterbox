#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-mobile-restart.XXXXXX)
engine_dir=$(./scripts/build-golem-test-engine.sh)
products=build/GolemPlan/Build/Products/Debug
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" tests/mobile-session-controls/main.swift
CHATTERBOX_PREFERENCES_SUITE="chatterbox.mobile-restart.$(basename "$fixture")" CHATTERBOX_LEGACY_RUNTIME=1 CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0 "$fixture/test"
