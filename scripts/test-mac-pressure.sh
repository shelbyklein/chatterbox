#!/bin/bash
# The Mac's pressure indicator (Core/Chatterbox/Views/MacPressureViews.swift): the toolbar badge at
# OK, Busy and Overloaded, its readings popover and the menu bar panel's row, rendered to PNGs
# (CHATTERBOX_PRESSURE_SHOTS=dir copies them there). Needs the Mac app built (build/DerivedData).
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-mac-pressure.XXXXXX)
engine_dir=$(./scripts/build-test-engine.sh)
products=build/DerivedData/Build/Products/Debug
sed 's/@testable import Chatterbox$/@testable import ChatterboxTestEngine/' tests/mac-pressure/main.swift > "$fixture/main.swift"
export CHATTERBOX_LEGACY_RUNTIME=1
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" "$fixture/main.swift"
CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_COMPANION_PORT=0 "$fixture/test"
if [[ -n "${CHATTERBOX_PRESSURE_SHOTS:-}" ]]; then mkdir -p "$CHATTERBOX_PRESSURE_SHOTS"; cp "$fixture"/pressure-*.png "$CHATTERBOX_PRESSURE_SHOTS/"; fi
