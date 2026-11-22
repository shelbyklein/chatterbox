#!/bin/bash
# The always-on Desk (plans/always-on-desk.md): its inbox, built as the service builds it.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/source-list.sh
fixture=$(mktemp -d /tmp/chatterbox-test-desk-inbox.XXXXXX)
trap 'echo "Desk inbox test artifacts: $fixture"' EXIT
./scripts/runtime-sources.sh > "$fixture/sources"
check_source_list "$fixture/sources"
swiftc -D DEBUG -D CHATTERBOX_HEADLESS -whole-module-optimization -Onone -o "$fixture/test" @"$fixture/sources" tests/desk-inbox/main.swift
mkdir -p "$fixture/data"
CHATTERBOX_DATA_DIR="$fixture/data" CHATTERBOX_HOST_DIR="$fixture/host" CHATTERBOX_PREFERENCES_SUITE="chatterbox.deskinbox.$(basename "$fixture")" "$fixture/test"
