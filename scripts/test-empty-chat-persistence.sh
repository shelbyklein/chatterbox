#!/bin/bash
# Empty chats that carry user intent (name, Studio, agent/model) survive a relaunch; blank ones don't.
# Needs a built app first: xcodebuild -scheme Chatterbox -derivedDataPath build/DerivedData build
set -euo pipefail
cd "$(dirname "$0")/.."
products=build/DerivedData/Build/Products/Debug
task_dir=$(mktemp -d /tmp/chatterbox-empty-chat.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data"
export CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_AGENT_PORT=0
export CHATTERBOX_COMPANION_PORT=47440
mkdir -p "$CHATTERBOX_DATA_DIR" "$CHATTERBOX_HOST_DIR"
find Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift | sort > "$task_dir/files.txt"
swiftc -D DEBUG -Onone \
  -I "$products" "$products/SwiftTerm.o" \
  -framework AVKit -framework WebKit -framework PDFKit \
  -o "$task_dir/test" @"$task_dir/files.txt" tests/empty-chat-persistence/main.swift
"$task_dir/test"
echo "Empty chat persistence artifacts: $task_dir"
