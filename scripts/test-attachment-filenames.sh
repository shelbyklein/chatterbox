#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-attachment-filenames.XXXXXX)
products=build/DerivedData/Build/Products/Debug
mkdir -p "$products"
swiftc -o "$products/attachment-filename-tests" \
  Core/Chatterbox/Support/JSON.swift Core/Chatterbox/Support/Attachments.swift \
  tests/attachment-filenames/main.swift
CHATTERBOX_DATA_DIR="$fixture" "$products/attachment-filename-tests"
