#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-mini-ack.XXXXXX)
export CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_HOST_DIR="$fixture/host"
export CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0
mkdir -p "$fixture/Dot"
cp -R /Users/shelbyklein/Chatterbox/Dot/Avatar "$fixture/Dot/Avatar"
products=build/DerivedData/Build/Products/Debug
dylib="$(pwd)/$products/Chatterbox.app/Contents/MacOS"
swiftc -I "$products" "$dylib/Chatterbox.debug.dylib" -Xlinker -rpath -Xlinker "$dylib" -D DEBUG -o "$fixture/test" tests/mini-ack/main.swift
"$fixture/test"
echo "Proof: $fixture"
