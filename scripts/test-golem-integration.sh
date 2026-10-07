#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-chatterbox-daemon.sh
/usr/bin/python3 tests/golem-integration/rpc.py
/usr/bin/python3 tests/golem-integration/companion.py
./scripts/test-golem-projection.sh
