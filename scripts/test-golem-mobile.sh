#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project Chatterbox.xcodeproj -scheme ChatterboxMobile -sdk iphonesimulator -configuration Debug -derivedDataPath build/GolemMobilePlan CODE_SIGNING_ALLOWED=NO build
cd "${GOLEM_REPO:-../Golem}"
xcodebuild -project Golem.xcodeproj -scheme GolemMobile -sdk iphonesimulator -configuration Debug -derivedDataPath build/GolemMobilePlan CODE_SIGNING_ALLOWED=NO build
