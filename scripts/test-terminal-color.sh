#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-terminal-color.XXXXXX)
products=build/DerivedData/Build/Products/Debug
dylib="$PWD/$products/Chatterbox.app/Contents/MacOS"
swiftc -I "$products" "$dylib/Chatterbox.debug.dylib" -Xlinker -rpath -Xlinker "$dylib" -D DEBUG -o "$fixture/test" tests/terminal-color/main.swift
CHATTERBOX_DATA_DIR="$fixture" SHELL=/bin/zsh "$fixture/test"
echo "Proof: $fixture/prompt.png"
