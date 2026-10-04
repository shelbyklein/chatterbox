#!/bin/bash
# Times chat switching against copies of your saved chats (read-only; nothing is resumed).
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
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); r.pop("claudeHost",None); r.pop("codexHost",None); json.dump(r,open(sys.argv[2],"w"))' \
    "$file" "$CHATTERBOX_DATA_DIR/Conversations/$(basename "$file")"
done
find Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$test_dir/files.txt"
products=build/DerivedData/Build/Products/Debug
[ -f "$products/SwiftTerm.o" ] || xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -configuration Debug \
  -derivedDataPath build/DerivedData build -quiet
# -O, like the shipped app's hot paths; Debug-only code paths stay on via -D DEBUG.
swiftc -I "$products" "$products/SwiftTerm.o" -D DEBUG -whole-module-optimization -O -o "$test_dir/test" \
  @"$test_dir/files.txt" tests/chat-switch-perf/main.swift
if [ -n "${PERF_SAMPLE:-}" ]; then
  # Profile the switching rounds: a call-graph sample of the main thread lands in $PERF_SAMPLE.
  "$test_dir/test" & pid=$!
  sleep 6; sample "$pid" 8 -mayDie -file "$PERF_SAMPLE" >/dev/null 2>&1 || true
  wait "$pid"
else
  "$test_dir/test"
fi
