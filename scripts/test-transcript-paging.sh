#!/bin/bash
# Checks that drawing only the newest transcript rows matches grouping the whole history.
# Reads saved chats (read-only). Needs a built tree: xcodebuild -scheme Chatterbox -derivedDataPath build/DerivedData build
set -euo pipefail
cd "$(dirname "$0")/.."
products=build/DerivedData/Build/Products/Debug
test_dir=$(mktemp -d /tmp/chatterbox-paging.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
export CHATTERBOX_DATA_DIR="$test_dir/data" CHATTERBOX_HOST_DIR="$test_dir/host" CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$test_dir/files.txt"
swiftc -O -D DEBUG -whole-module-optimization -o "$test_dir/test" -I "$products" @"$test_dir/files.txt" "$products/SwiftTerm.o" \
  -framework AVKit -framework WebKit -framework PDFKit tests/transcript-paging/main.swift
"$test_dir/test" "$@"
