#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-history-on-scroll.XXXXXX)
products=build/DerivedData/Build/Products/Debug
sed '/@testable import Chatterbox$/d' tests/history-on-scroll/main.swift > "$fixture/main.swift"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$fixture/sources"
export CHATTERBOX_LEGACY_RUNTIME=1
swiftc -I "$products" "$products/SwiftTerm.o" -D DEBUG -whole-module-optimization -Onone \
  -o "$products/history-loading-tests" @"$fixture/sources" "$fixture/main.swift"
mkdir -p design/lazy-session-loading
CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0 \
  HISTORY_CAPTURE="$PWD/design/lazy-session-loading/manual-history.png" "$products/history-loading-tests"
