#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-sidechat.XXXXXX)
products=build/DerivedData/Build/Products/Debug
sed '/@testable import Chatterbox$/d' tests/sidechat/main.swift > "$fixture/main.swift"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$fixture/sources"
export CHATTERBOX_LEGACY_RUNTIME=1
swiftc -I "$products" "$products/SwiftTerm.o" -D DEBUG -whole-module-optimization -Onone \
  -o "$products/sidechat-tests" @"$fixture/sources" "$fixture/main.swift"
CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_COMPANION_PORT=0 CHATTERBOX_TEST_SIDEBAR_ONLY=280 "$products/sidechat-tests"
