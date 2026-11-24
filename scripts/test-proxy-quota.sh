#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
products=build/DerivedData/Build/Products/Debug
test_dir=$(mktemp -d /tmp/chatterbox-proxy-quota.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$test_dir/files.txt"
swiftc -D DEBUG -whole-module-optimization -Onone -o "$test_dir/test" \
  -I "$products" @"$test_dir/files.txt" "$products/SwiftTerm.o" \
  -framework AVKit -framework WebKit -framework PDFKit tests/proxy-quota/main.swift
mkdir -p build/test-logs; "$test_dir/test" "$PWD/build/test-logs/proxy-quota.png"
