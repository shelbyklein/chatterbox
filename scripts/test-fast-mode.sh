#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/chatterbox-fast.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data"
export CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_AGENT_PORT=0
export CHATTERBOX_COMPANION_PORT=19650
mkdir -p "$CHATTERBOX_DATA_DIR"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name 'ChatterboxApp.swift' | sort > "$task_dir/files.txt"
engine_key=$({ swiftc --version; cat "$task_dir/files.txt"; while IFS= read -r source; do cat "$source"; done < "$task_dir/files.txt"; } | shasum -a 256 | cut -c 1-16)
engine_dir="/tmp/chatterbox-mini-engine.$engine_key"
if [[ ! -f "$engine_dir/libChatterboxTestEngine.dylib" || ! -f "$engine_dir/ChatterboxTestEngine.swiftmodule" ]]; then
  mkdir -p "$engine_dir"
  swiftc -I build/DerivedData/Build/Products/Debug build/DerivedData/Build/Products/Debug/SwiftTerm.o -D DEBUG -whole-module-optimization -Onone -enable-testing \
    -emit-library -emit-module -module-name ChatterboxTestEngine \
    -emit-module-path "$engine_dir/ChatterboxTestEngine.swiftmodule" \
    -o "$engine_dir/libChatterboxTestEngine.dylib" @"$task_dir/files.txt"
fi
mkdir -p "$task_dir/PushTest.app/Contents/MacOS" "$task_dir/PushTest.app/Contents/Resources"
cp build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/Resources/Assets.car "$task_dir/PushTest.app/Contents/Resources/"
/usr/bin/python3 - "$task_dir" <<'PYINFO'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1])/'PushTest.app/Contents/Info.plist'
p.write_bytes(plistlib.dumps({'CFBundleExecutable':'test','CFBundlePackageType':'APPL','CFBundleName':'PushTest'}))
PYINFO
swiftc -I "$engine_dir" -I build/DerivedData/Build/Products/Debug -L "$engine_dir" -lChatterboxTestEngine \
  -Xlinker -rpath -Xlinker "$engine_dir" -o "$task_dir/PushTest.app/Contents/MacOS/test" tests/fast-mode/main.swift
"$task_dir/PushTest.app/Contents/MacOS/test"
echo "Fast mode test artifacts: $task_dir"
