#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-github-pin.XXXXXX)
engine_dir=$(./scripts/build-golem-test-engine.sh)
products=build/GolemPlan/Build/Products/Debug
swiftc -I "$products" -I "$engine_dir" -L "$engine_dir" -lChatterboxTestEngine -Xlinker -rpath -Xlinker "$engine_dir" -D DEBUG -o "$fixture/test" tests/github-pin/main.swift
CHATTERBOX_DATA_DIR="$fixture" "$fixture/test"
