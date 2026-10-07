#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-model-layout.XXXXXX)
# Exercise the production SwiftUI Layout without needing the entire agent runtime.
/usr/bin/python3 - "$fixture" <<'PY'
import sys
from pathlib import Path
source=Path('Core/Chatterbox/Views/ChatView.swift').read_text()
layout=source[source.index('private struct ComposerStatusLayout: Layout'):]
Path(sys.argv[1],'layout.swift').write_text('import SwiftUI\n'+layout.replace('private struct ComposerStatusLayout','struct ComposerStatusLayout',1))
PY
swiftc "$fixture/layout.swift" tests/model-status-layout/main.swift -o "$fixture/test"
ASSERT_LAYOUT=1 "$fixture/test"
