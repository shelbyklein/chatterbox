#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-sidechat.XXXXXX)
engine_dir=$(./scripts/build-golem-test-engine.sh)
products=build/DerivedData/Build/Products/Debug
sed 's/@testable import Chatterbox$/@testable import ChatterboxTestEngine/' tests/sidechat/main.swift > "$fixture/main.swift"
export CHATTERBOX_LEGACY_RUNTIME=1
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" "$fixture/main.swift"
CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0 CHATTERBOX_TEST_SIDEBAR_ONLY=280 "$fixture/test"
