#!/bin/bash
# AppModel's session index (sidechats, sidequests, worktrees by parent): looked up, not scanned
# per thread, and rebuilt only when a session's place changes. See tests/session-index.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-session-index.XXXXXX)
engine_dir=$(./scripts/build-test-engine.sh)
products=build/DerivedData/Build/Products/Debug
sed 's/@testable import Chatterbox$/@testable import ChatterboxTestEngine/' tests/session-index/main.swift > "$fixture/main.swift"
export CHATTERBOX_LEGACY_RUNTIME=1
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" "$fixture/main.swift"
CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_COMPANION_PORT=0 "$fixture/test"
