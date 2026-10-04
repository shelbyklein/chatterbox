#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-chatterbox-daemon.sh
python3 tests/golem-integration/rpc.py
python3 tests/golem-integration/companion.py
./scripts/test-golem-projection.sh
