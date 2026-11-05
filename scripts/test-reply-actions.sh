#!/bin/bash
# Action buttons under a reply (```actions): parsed, live only on the newest reply, a tap sends
# its message into the thread, then the row greys out with the one used ticked.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-reply-actions.XXXXXX)
engine_dir=$(./scripts/build-test-engine.sh)
products=build/DerivedData/Build/Products/Debug
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" tests/reply-actions/main.swift
CHATTERBOX_DATA_DIR="$fixture" "$fixture/test"
if [[ -n "${SCREENSHOTS:-}" ]]; then mkdir -p "$SCREENSHOTS"; cp "$fixture"/*.png "$SCREENSHOTS/"; fi
