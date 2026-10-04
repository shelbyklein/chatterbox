#!/bin/bash
# Checks the markdown/path-link caches against the uncached functions, and times them.
# Needs a built tree: xcodebuild -scheme Chatterbox -derivedDataPath build/DerivedData build
set -euo pipefail
cd "$(dirname "$0")/.."
products=build/DerivedData/Build/Products/Debug
test_dir=$(mktemp -d /tmp/chatterbox-mdcache.XXXXXX)
trap 'echo "Test artifacts: $test_dir"' EXIT
export CHATTERBOX_MDCACHE_DIR="$test_dir"
find Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$test_dir/files.txt"
swiftc -D DEBUG -whole-module-optimization -Onone -o "$test_dir/test" \
  -I "$products" @"$test_dir/files.txt" "$products/SwiftTerm.o" \
  -framework AVKit -framework WebKit -framework PDFKit tests/markdown-cache/main.swift
"$test_dir/test"
