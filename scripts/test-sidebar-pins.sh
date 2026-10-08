#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-sidebar-pins.XXXXXX)
engine_dir=$(./scripts/build-golem-test-engine.sh)
products=build/DerivedData/Build/Products/Debug
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" tests/sidebar-pins/main.swift
CHATTERBOX_PREFERENCES_SUITE=chatterbox.test.sidebarpins CHATTERBOX_DATA_DIR="$fixture" "$fixture/test"
