#!/bin/bash
# Usage warnings (50/20/5% left) and burn rate: Core/Chatterbox/Engine/Usage.swift.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-usage-warnings.XXXXXX)
engine_dir=$(./scripts/build-test-engine.sh)
products=build/DerivedData/Build/Products/Debug
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" tests/usage-warnings/main.swift
CHATTERBOX_LEGACY_RUNTIME=1 CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_PREFERENCES_SUITE="usage-warnings-$$" "$fixture/test"
