#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
artifacts=$(mktemp -d /tmp/chatterbox-pdf-mac.XXXXXX)
trap 'echo "PDF server artifacts: $artifacts"' EXIT
export CHATTERBOX_DATA_DIR="$artifacts/data"
export CHATTERBOX_HOST_DIR="$artifacts/host"
# A free port of this run's own (test-hygiene.sh), so two runs never collide.
export CHATTERBOX_COMPANION_PORT=$(free_port)
mkdir -p "$CHATTERBOX_DATA_DIR"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name 'ChatterboxApp.swift' > "$artifacts/files.txt"
swiftc -I build/DerivedData/Build/Products/Debug build/DerivedData/Build/Products/Debug/SwiftTerm.o -framework AVKit -framework WebKit -framework PDFKit -D DEBUG -whole-module-optimization -Onone -o "$artifacts/test" @"$artifacts/files.txt" tests/companion-pdf/main.swift
"$artifacts/test"
