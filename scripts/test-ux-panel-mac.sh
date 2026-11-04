#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
# UX panel tour, Mac (tests/ux-panel-mac): renders the main window, an approval and Settings
# from stand-in sessions for the design review screenshots. Evidence: ux-*.png in the fixture folder.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-ux-panel-mac.XXXXXX)
engine_dir=$(./scripts/build-test-engine.sh)
products=build/DerivedData/Build/Products/Debug
sed 's/@testable import Chatterbox$/@testable import ChatterboxTestEngine/' tests/ux-panel-mac/main.swift > "$fixture/main.swift"
export CHATTERBOX_LEGACY_RUNTIME=1
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" "$fixture/main.swift"
cp "$products/Chatterbox.app/Contents/Resources/Assets.car" "$fixture/Assets.car"
CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_COMPANION_PORT=0 "$fixture/test"
