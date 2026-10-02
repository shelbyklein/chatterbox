#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
artifacts=$(mktemp -d /tmp/chatterbox-pdf-mac.XXXXXX)
trap 'echo "PDF server artifacts: $artifacts"' EXIT
export CHATTERBOX_DATA_DIR="$artifacts/data"
export CHATTERBOX_HOST_DIR="$artifacts/host"
export CHATTERBOX_AGENT_PORT=19648
export CHATTERBOX_COMPANION_PORT=0
mkdir -p "$CHATTERBOX_DATA_DIR"
rg --files Chatterbox Shared -g '*.swift' -g '!ChatterboxApp.swift' > "$artifacts/files.txt"
swiftc -D DEBUG -whole-module-optimization -Onone -o "$artifacts/test" @"$artifacts/files.txt" tests/companion-pdf/main.swift
"$artifacts/test"
