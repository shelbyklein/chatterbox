#!/bin/bash
# T1 of plans/mobile-remote-desktop.md: RoyalVNCKit signs in to this Mac's Screen Sharing and
# saves one frame. Asks for the Mac password in a dialog (kept in memory only).
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/chatterbox-vnc-spike.XXXXXX)
swift build --package-path tests/vnc-spike --scratch-path build/DerivedData/vnc-spike -c debug 2>&1 | grep -E 'error|warning: unable|Compiling vnc|Build complete' | tail -5
build/DerivedData/vnc-spike/debug/vnc-spike "$out/frame.png"
echo "Evidence: $out/frame.png"
