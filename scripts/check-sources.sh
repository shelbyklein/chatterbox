#!/bin/bash
# Checks that the build inputs agree before shipping (ship.sh runs it):
#  - Chatterbox.xcodeproj matches project.yml. A file added to Core (often by another chat)
#    doesn't build in Xcode until the project is regenerated; this regenerates it and stops
#    so the change gets reviewed and committed.
#  - the service's hand-written source lists name only real files, once each.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/source-list.sh
xcodegen generate --quiet
if ! git diff --quiet -- Chatterbox.xcodeproj; then
  echo "The Xcode project was out of date with project.yml; it has been regenerated:" >&2
  git diff --stat -- Chatterbox.xcodeproj >&2
  echo "Review it, stage it (git add Chatterbox.xcodeproj) and ship again." >&2
  exit 1
fi
manifest=$(mktemp /tmp/chatterbox-sources.XXXXXX)
trap 'rm -f "$manifest"' EXIT
./scripts/runtime-sources.sh > "$manifest"
check_source_list "$manifest"
echo "Sources check out."
