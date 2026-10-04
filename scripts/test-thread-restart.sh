#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-thread-restart.XXXXXX)
export CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_HOST_DIR="$fixture/host"
export CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0
export CHATTERBOX_HOST_BINARY="$(pwd)/build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/MacOS/ChatterboxHost"
cp tests/thread-restart/fake-*.py "$fixture/"
chmod +x "$fixture"/fake-*.py
products=build/DerivedData/Build/Products/Debug
dylib="$(pwd)/$products/Chatterbox.app/Contents/MacOS"
swiftc -I "$products" "$dylib/Chatterbox.debug.dylib" -Xlinker -rpath -Xlinker "$dylib" -D DEBUG -o "$fixture/test" tests/thread-restart/main.swift
"$fixture/test"
echo "Proof: $fixture"
