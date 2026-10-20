#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-tools-settings.XXXXXX); mkdir -p "$fixture/home"
products=build/DerivedData/Build/Products/Debug
sed '/@testable import ChatterboxTestEngine/d' tests/tools-settings/main.swift > "$fixture/main.swift"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$fixture/sources"
export CHATTERBOX_LEGACY_RUNTIME=1
swiftc -I "$products" "$products/SwiftTerm.o" -D DEBUG -whole-module-optimization -Onone \
  -o "$products/tools-settings-tests" @"$fixture/sources" "$fixture/main.swift"
CHATTERBOX_PREFERENCES_SUITE=chatterbox.test.toolssettings CHATTERBOX_TOOLS_HOME="$fixture/home" CHATTERBOX_DATA_DIR="$fixture" "$products/tools-settings-tests"
