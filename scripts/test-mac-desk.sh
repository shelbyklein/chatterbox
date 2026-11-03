#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
# The Desk on the Mac (plans/front-desk.md): renders Home's Desk page from stand-in sessions
# and a stand-in service Desk, checks its sections, summary and "desk" requests.
# Evidence: desk-*.png in the fixture folder it prints.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-mac-desk.XXXXXX)
engine_dir=$(./scripts/build-test-engine.sh)
products=build/DerivedData/Build/Products/Debug
export CHATTERBOX_LEGACY_RUNTIME=1
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" tests/mac-desk/main.swift
cp "$products/Chatterbox.app/Contents/Resources/Assets.car" "$fixture/Assets.car"
CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_COMPANION_PORT=0 "$fixture/test"
