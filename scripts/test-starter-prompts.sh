#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-starters.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
swiftc Core/Shared/Backend.swift Core/Shared/StarterPrompts.swift tests/starter-prompts/main.swift -o "$fixture/test"
"$fixture/test"
