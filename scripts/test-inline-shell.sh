#!/bin/bash
# Stress-tests "!" shell commands: bounded output, Stop/shutdown killing the process tree,
# and normal commands. Uses an isolated data dir; builds the engine library into /tmp.
# Needs a prior `xcodebuild -scheme Chatterbox -derivedDataPath build/DerivedData build` (for SwiftTerm).
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/chatterbox-inline-shell.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data"
export CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_AGENT_PORT=0
export CHATTERBOX_COMPANION_PORT=47421
mkdir -p "$CHATTERBOX_DATA_DIR"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift | sort > "$task_dir/files.txt"
engine_key=$({ swiftc --version; cat "$task_dir/files.txt"; while IFS= read -r source; do cat "$source"; done < "$task_dir/files.txt"; } | shasum -a 256 | cut -c 1-16)
engine_dir="/tmp/chatterbox-mini-engine.$engine_key"
if [[ ! -f "$engine_dir/libChatterboxTestEngine.dylib" || ! -f "$engine_dir/ChatterboxTestEngine.swiftmodule" ]]; then
  mkdir -p "$engine_dir"
  swiftc -I build/DerivedData/Build/Products/Debug build/DerivedData/Build/Products/Debug/SwiftTerm.o -D DEBUG -whole-module-optimization -Onone -enable-testing \
    -emit-library -emit-module -module-name ChatterboxTestEngine \
    -emit-module-path "$engine_dir/ChatterboxTestEngine.swiftmodule" \
    -o "$engine_dir/libChatterboxTestEngine.dylib" @"$task_dir/files.txt"
fi
swiftc -I build/DerivedData/Build/Products/Debug -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine \
  -Xlinker -rpath -Xlinker "$engine_dir" -o "$task_dir/inline-shell-test" tests/inline-shell/main.swift
"$task_dir/inline-shell-test"
echo "Inline shell test artifacts: $task_dir"
