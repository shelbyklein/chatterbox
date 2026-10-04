#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-/tmp/chatterbox-fade-proof}"
fixture=$(mktemp -d /tmp/chatterbox-columns.XXXXXX)
trap 'cp "$fixture"/*.png "$out/" 2>/dev/null || true; rm -rf "$fixture"' EXIT
mkdir -p "$out"
swiftc Chatterbox/Views/ChatSwitchTransition.swift tests/chat-switch/Coordinator.swift -o "$fixture/policy"
"$fixture/policy"
python3 - "$fixture" <<'PY'
import pathlib,json,shutil,sys
out=pathlib.Path(sys.argv[1]);(out/'Conversations').mkdir()
source=pathlib.Path.home()/'Library/Application Support/Chatterbox/Conversations'
for f in source.glob('*.json'):
 r=json.loads(f.read_text())
 if not (r.get('isDot') or r.get('projectFolder')=='/Users/shelbyklein/Vibes/Chatterbox'):continue
 for k in ['claudeHost','codexHost']:r.pop(k,None)
 (out/'Conversations'/f.name).write_text(json.dumps(r))
shutil.copytree(pathlib.Path.home()/'Chatterbox/Dot/Avatar',out/'Dot/Avatar')
shutil.copy2(source.parent/'Studios.json',out/'Studios.json')
# Preserve exact copies used by this run for repeatable regression checks.
shutil.copytree(out,pathlib.Path('/tmp/chatterbox-columns-fixture-last'),dirs_exist_ok=True)
PY
export CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_HOST_DIR="$fixture/host"
export CHATTERBOX_AGENT_PORT=47491 CHATTERBOX_COMPANION_PORT=47492
products=build/DerivedData/Build/Products/Debug
dylib="$(pwd)/$products/Chatterbox.app/Contents/MacOS"
# Use the actual testable Debug module/library rather than recompiling every app file.
swiftc -I "$products" "$dylib/Chatterbox.debug.dylib" -Xlinker -rpath -Xlinker "$dylib" -D DEBUG -o "$fixture/test" tests/chat-switch/main.swift
cp "$fixture/test" "$out/test-bin"
"$fixture/test"
cp "$fixture"/*.png "$out/"
