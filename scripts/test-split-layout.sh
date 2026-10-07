#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
# Measures the main window's columns against copies of your saved chats (read-only; nothing is resumed).
# Usage: scripts/test-split-layout.sh <chat UUID> [out dir]   (SPLIT_WIDTHS=1600,900 to choose widths)
set -euo pipefail
cd "$(dirname "$0")/.."
chat="$1"
out="${2:-/tmp/chatterbox-split-captures}"
source_dir="$HOME/Library/Application Support/Chatterbox/Conversations"
test_dir=$(mktemp -d /tmp/chatterbox-split.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
export CHATTERBOX_DATA_DIR="$test_dir"
export CHATTERBOX_HOST_DIR="$test_dir/host"
export CHATTERBOX_AGENT_PORT="${SPLIT_PORT:-47471}"
export CHATTERBOX_COMPANION_PORT=$((${SPLIT_PORT:-47471} + 1))
export SPLIT_CHAT="$chat"
mkdir -p "$CHATTERBOX_DATA_DIR/Conversations" "$out"
# Copies only, with background-host links removed so no agent is reattached.
/usr/bin/python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); r.pop("claudeHost",None); r.pop("codexHost",None); json.dump(r,open(sys.argv[2],"w"))' \
  "$source_dir/$chat.json" "$CHATTERBOX_DATA_DIR/Conversations/$chat.json"
[ -f "$HOME/Library/Application Support/Chatterbox/Studios.json" ] && cp "$HOME/Library/Application Support/Chatterbox/Studios.json" "$CHATTERBOX_DATA_DIR/"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$test_dir/files.txt"
products=build/DerivedData/Build/Products/Debug
[ -f "$products/SwiftTerm.o" ] || xcodebuild -scheme Chatterbox -derivedDataPath build/DerivedData build -quiet
swiftc -I "$products" "$products/SwiftTerm.o" -D DEBUG -framework AVKit -framework WebKit -framework PDFKit \
  -o "$test_dir/test" @"$test_dir/files.txt" tests/split-layout/main.swift
"$test_dir/test"
cp "$test_dir"/*.png "$out/" 2>/dev/null || true
