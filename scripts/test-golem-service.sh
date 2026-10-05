#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-chatterbox-daemon.sh
./scripts/build-golem-service.sh
/usr/bin/python3 tests/golem-integration/service.py
/usr/bin/python3 tests/golem-integration/policies.py
