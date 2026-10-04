#!/bin/sh
set -e
cd "$(dirname "$0")/.."
exec "${GOLEM_REPO:-../Golem}/scripts/install-golem-rig.sh" "$@"
