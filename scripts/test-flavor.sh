#!/bin/bash
# Chatterbox's identities, real and Dev (Core/Shared/Flavor.swift): the real ones are exactly
# what they were before Chatterbox Dev, and Dev's are all its own. See tests/flavor.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-test-flavor.XXXXXX)
sources=(Core/Shared/Flavor.swift Core/Shared/CompanionAPI.swift Core/Shared/AppPreferences.swift
  Core/Chatterbox/Support/JSON.swift Core/Chatterbox/Support/HostProtocol.swift tests/flavor/main.swift)
swiftc -D CHATTERBOX_HEADLESS -o "$fixture/real" "${sources[@]}"
swiftc -D CHATTERBOX_HEADLESS -D CHATTERBOX_DEV -o "$fixture/dev" "${sources[@]}"
env -u CHATTERBOX_HOST_DIR -u CHATTERBOX_PREFERENCES_SUITE "$fixture/real" real
env -u CHATTERBOX_HOST_DIR -u CHATTERBOX_PREFERENCES_SUITE "$fixture/dev" dev
