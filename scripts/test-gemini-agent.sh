#!/bin/bash
# Gemini (Antigravity CLI over ACP) as a chat's agent, through the real ChatterboxHost and a
# fake agy (tests/gemini-agent/fake-agy.py). plans/gemini-agent.md.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-gemini-agent.XXXXXX)
export CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_HOST_DIR="$fixture/host"
export CHATTERBOX_COMPANION_PORT=0
export CHATTERBOX_HOST_BINARY="$(pwd)/build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/Helpers/ChatterboxHost.app/Contents/MacOS/ChatterboxHost"
cp tests/gemini-agent/fake-agy.py "$fixture/"
chmod +x "$fixture/fake-agy.py"
engine_dir=$(./scripts/build-test-engine.sh)
products=build/DerivedData/Build/Products/Debug
sed 's/@testable import Chatterbox$/@testable import ChatterboxTestEngine/' tests/gemini-agent/main.swift > "$fixture/main.swift"
export CHATTERBOX_LEGACY_RUNTIME=1
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" "$fixture/main.swift"
"$fixture/test"
echo "Gemini agent test artifacts: $fixture"
