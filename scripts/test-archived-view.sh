#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-archive-view.XXXXXX)
products=build/DerivedData/Build/Products/Debug
if [[ ! -f "$products/Chatterbox.app/Contents/Resources/Assets.car" ]]; then
  xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -configuration Debug -derivedDataPath build/DerivedData -quiet build
fi
engine_dir=$(./scripts/build-test-engine.sh)
sed 's/@testable import Chatterbox$/@testable import ChatterboxTestEngine/' tests/archived-view/main.swift > "$fixture/main.swift"
export CHATTERBOX_LEGACY_RUNTIME=1
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" "$fixture/main.swift"
cp "$products/Chatterbox.app/Contents/Resources/Assets.car" "$fixture/Assets.car"
CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_COMPANION_PORT=0 "$fixture/test"
mkdir -p build/archived-view-native
cp "$fixture/"*.png build/archived-view-native/
echo "Native captures: build/archived-view-native"
