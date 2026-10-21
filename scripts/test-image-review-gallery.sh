#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-image-review.XXXXXX)
products=build/DerivedData/Build/Products/Debug
mkdir -p "$products"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$fixture/sources"
sed '/@testable import ChatterboxTestEngine$/d' tests/image-review-gallery/main.swift > "$fixture/main.swift"
export CHATTERBOX_LEGACY_RUNTIME=1
swiftc -I "$products" "$products/SwiftTerm.o" -D DEBUG -whole-module-optimization -Onone \
  -o "$products/image-review-tests" @"$fixture/sources" "$fixture/main.swift"
CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0 "$products/image-review-tests"
