#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-command-center.XXXXXX)
products=build/DerivedData/Build/Products/Debug
dylib="$PWD/$products/Chatterbox.app/Contents/MacOS"
swiftc -I "$products" "$dylib/Chatterbox.debug.dylib" -Xlinker -rpath -Xlinker "$dylib" -D DEBUG -o "$fixture/test" tests/command-center/main.swift
cp "$products/Chatterbox.app/Contents/Resources/Assets.car" "$fixture/Assets.car"
CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0 "$fixture/test"
