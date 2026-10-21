#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
products=build/DerivedData/Build/Products/Debug
mkdir -p "$products"
swiftc Core/Shared/CompanionAPI.swift Core/Chatterbox/Engine/ProxyQuota.swift tests/proxy-quota/main.swift -o "$products/proxy-quota-tests"
"$products/proxy-quota-tests" "$@"
