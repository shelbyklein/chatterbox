#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/chatterbox-quota-test.XXXXXX)
trap 'rm -rf "$work"' EXIT
swiftc Core/Chatterbox/Engine/ProxyQuota.swift tests/proxy-quota/main.swift -o "$work/check"
"$work/check" "$@"
