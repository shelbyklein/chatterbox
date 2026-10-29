#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-place-suggestion.XXXXXX)
swiftc -o "$fixture/test" Core/Shared/PlaceSuggestion.swift tests/place-suggestion/main.swift
"$fixture/test"
