#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
# Thread sidebar, Mac (tests/thread-sidebar-mac): About this thread down the right of a chat.
# Sections shown and hidden, header places, the toolbar toggle, the narrow slide-over; and the
# old column of icon buttons gone from the chat. Screenshots go to design/thread-sidebar.
set -euo pipefail
cd "$(dirname "$0")/.."
# The column of icon buttons is gone: none of its tiles is drawn by the chat any more.
if grep -nE 'BriefButton\(|NotesButton\(|RepoButton\(|SessionImages\(|ChatQuickActions\(|WorkThreadButton\(|SidequestButton\(|PCErrandButton\(|WorkStrip\(|iconOnly: true' Chatterbox/Views/ChatView.swift; then
  echo "FAIL the chat still draws the old column of buttons or the Work strip"; exit 1
fi
echo "ok   the chat no longer draws the old column of buttons or the Work strip"
fixture=$(mktemp -d /tmp/chatterbox-thread-sidebar-mac.XXXXXX)
engine_dir=$(./scripts/build-test-engine.sh)
products=build/DerivedData/Build/Products/Debug
sed 's/@testable import Chatterbox$/@testable import ChatterboxTestEngine/' tests/thread-sidebar-mac/main.swift > "$fixture/main.swift"
export CHATTERBOX_LEGACY_RUNTIME=1
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" "$fixture/main.swift"
cp "$products/Chatterbox.app/Contents/Resources/Assets.car" "$fixture/Assets.car"
CHATTERBOX_DATA_DIR="$fixture" CHATTERBOX_COMPANION_PORT=0 CHATTERBOX_PREFERENCES_SUITE="chatterbox-thread-sidebar-test" "$fixture/test"
mkdir -p design/thread-sidebar
cp "$fixture"/mac-sidebar*.png design/thread-sidebar/
echo "Screenshots: design/thread-sidebar/mac-sidebar*.png"
