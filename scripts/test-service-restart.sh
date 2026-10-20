#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/chatterbox-service-restart.XXXXXX)
products=build/DerivedData/Build/Products/Debug
mkdir -p "$products"
swiftc Core/Chatterbox/Support/BackgroundServiceRestart.swift tests/service-restart/main.swift \
  -o "$products/service-restart-tests"
"$products/service-restart-tests" "$task_dir"
