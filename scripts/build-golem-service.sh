#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
golem_repo=${GOLEM_REPO:-../Golem}
[[ -f "$golem_repo/project.yml" ]] || { echo "Set GOLEM_REPO to the separate Golem checkout." >&2; exit 1; }
golem_repo=$(cd "$golem_repo" && pwd)
"$golem_repo/scripts/build-golem-service.sh"
mkdir -p build/runtime
cp "$golem_repo/build/runtime/golemd" build/runtime/golemd
