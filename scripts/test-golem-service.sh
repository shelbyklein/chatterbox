#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-chatterbox-daemon.sh
./scripts/build-golem-service.sh
python3 tests/golem-integration/service.py
python3 tests/golem-integration/policies.py
