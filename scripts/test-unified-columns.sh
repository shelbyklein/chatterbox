#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-/tmp/chatterbox-columns-proof}"
fixture=$(mktemp -d /tmp/chatterbox-columns.XXXXXX)
trap 'cp "$fixture"/*.png "$out/" 2>/dev/null || true; rm -rf "$fixture"' EXIT
mkdir -p "$out"
swiftc Chatterbox/Views/ChatColumnWidths.swift tests/unified-columns/Policy.swift -o "$fixture/policy"
"$fixture/policy"
/usr/bin/python3 - "$fixture" <<'PY'
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
export CHATTERBOX_AGENT_PORT=47481 CHATTERBOX_COMPANION_PORT=47482
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$fixture/files.txt"
products=build/DerivedData/Build/Products/Debug
swiftc -I "$products" "$products/SwiftTerm.o" -D DEBUG -framework AVKit -framework WebKit -framework PDFKit -o "$fixture/test" @"$fixture/files.txt" tests/unified-columns/main.swift
cp "$fixture/test" "$out/test-bin"
"$fixture/test"
cp "$fixture"/*.png "$out/"
