#!/bin/bash
# The service's pressure level (Core/ChatterboxRuntime/MacPressure.swift) from recorded readings:
# sustained load windows, swap growth, memory and thermal states, the 3-minute step down, and the
# thresholds read from preferences. Pure decisions; nothing on the Mac is read or touched.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-test-pressure.XXXXXX)
swiftc -o "$fixture/test" Core/ChatterboxRuntime/MacPressure.swift tests/pressure/main.swift
"$fixture/test"
# The companion API's reading, as the phone decodes it.
swiftc -D CHATTERBOX_HEADLESS -o "$fixture/companion" Core/Shared/Flavor.swift Core/Shared/CompanionAPI.swift Core/Shared/AppPreferences.swift \
  Core/Chatterbox/Support/JSON.swift Core/Chatterbox/Support/HostProtocol.swift tests/pressure-companion/main.swift
"$fixture/companion"
