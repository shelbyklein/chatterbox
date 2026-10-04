#!/bin/bash
# Claude task tools (TaskCreate/TaskUpdate/TaskList) mirrored as the chat's plan: deleting
# by id, empty list clears the plan, status/subject/order updates. No live agents.
set -euo pipefail
cd "$(dirname "$0")/.."
products="$PWD/build/DerivedData/Build/Products/Debug"
[[ -f "$products/SwiftTerm.o" ]] || { echo "Build first: xcodebuild -scheme Chatterbox -derivedDataPath build/DerivedData build" >&2; exit 1; }
task_dir=$(mktemp -d /tmp/chatterbox-claude-tasks.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data"
export CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_AGENT_PORT=0
export CHATTERBOX_COMPANION_PORT=47430
mkdir -p "$CHATTERBOX_DATA_DIR"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift | sort > "$task_dir/files.txt"
engine_key=$({ swiftc --version; echo "$products"; cat "$task_dir/files.txt"; while IFS= read -r source; do cat "$source"; done < "$task_dir/files.txt"; } | shasum -a 256 | cut -c 1-16)
engine_dir="/tmp/chatterbox-mini-engine.$engine_key"
if [[ ! -f "$engine_dir/libChatterboxTestEngine.dylib" || ! -f "$engine_dir/ChatterboxTestEngine.swiftmodule" ]]; then
  mkdir -p "$engine_dir"
  swiftc -I "$products" "$products/SwiftTerm.o" -framework AVKit -framework WebKit -framework PDFKit -D DEBUG -whole-module-optimization -Onone -enable-testing \
    -emit-library -emit-module -module-name ChatterboxTestEngine \
    -emit-module-path "$engine_dir/ChatterboxTestEngine.swiftmodule" \
    -o "$engine_dir/libChatterboxTestEngine.dylib" @"$task_dir/files.txt"
fi
swiftc -I "$engine_dir" -I "$products" -L "$engine_dir" -lChatterboxTestEngine \
  -Xlinker -rpath -Xlinker "$engine_dir" -o "$task_dir/test" tests/claude-tasks/main.swift
"$task_dir/test"
rm -rf "$task_dir"
