#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
# Renders Home's Studios page against copies of your chats (read-only) and checks thread image thumbnails.
# Usage: scripts/test-chat-switch-perf.sh [conversations dir]
set -euo pipefail
cd "$(dirname "$0")/.."
source_dir="${1:-$HOME/Library/Application Support/Chatterbox/Conversations}"
test_dir=$(mktemp -d /tmp/chatterbox-perf.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
export CHATTERBOX_DATA_DIR="$test_dir/data"
export CHATTERBOX_HOST_DIR="$test_dir/host"
export CHATTERBOX_AGENT_PORT=0
export CHATTERBOX_COMPANION_PORT=0
mkdir -p "$CHATTERBOX_DATA_DIR/Conversations"
# Copies only, with background-host links removed so no agent is reattached.
for file in "$source_dir"/*.json; do
  /usr/bin/python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); r.pop("claudeHost",None); r.pop("codexHost",None); json.dump(r,open(sys.argv[2],"w"))' \
    "$file" "$CHATTERBOX_DATA_DIR/Conversations/$(basename "$file")"
done
cp "$source_dir/../Studios.json" "$CHATTERBOX_DATA_DIR/" 2>/dev/null || true
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$test_dir/files.txt"
products=build/DerivedData/Build/Products/Debug
[ -f "$products/SwiftTerm.o" ] || xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -configuration Debug \
  -derivedDataPath build/DerivedData build -quiet
# -O, like the shipped app's hot paths; Debug-only code paths stay on via -D DEBUG.
swiftc -I "$products" "$products/SwiftTerm.o" -framework AVKit -framework WebKit -framework PDFKit -D DEBUG -whole-module-optimization -O -o "$test_dir/test" \
  @"$test_dir/files.txt" tests/home-thumbnails/main.swift
mkdir -p "$HOME/Chatterbox/Screenshots/home-thumbnails"
THUMB_OUT="$HOME/Chatterbox/Screenshots/home-thumbnails" "$test_dir/test"
