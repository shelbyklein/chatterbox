#!/bin/bash
# The service's idle-simulator sweep (Core/ChatterboxRuntime/SimulatorSweep.swift): which booted
# devices it shuts down (unused for 30 min by any process, Simulator window or Chatterbox test
# run) and which it keeps. Pure decisions against made-up devices; no simulator is touched.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-test-simulator-sweeper.XXXXXX)
swiftc -o "$fixture/test" Core/ChatterboxRuntime/SimulatorSweep.swift tests/simulator-sweeper/main.swift
"$fixture/test"
