#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-current-model.XXXXXX)
engine_dir=$(./scripts/build-golem-test-engine.sh)
products=build/GolemPlan/Build/Products/Debug
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" tests/current-model/main.swift
CHATTERBOX_LEGACY_RUNTIME=1 CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_HOST_DIR="$fixture/host" CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0 CHATTERBOX_HOST_BINARY="$PWD/build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/MacOS/ChatterboxHost" "$fixture/test"
