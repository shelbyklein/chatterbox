#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
artifacts=$(mktemp -d /tmp/chatterbox-pdf-cache.XXXXXX)
export CHATTERBOX_PDF_CACHE_DIR="$artifacts/cache"
swiftc -parse-as-library -D DEBUG Shared/CompanionAPI.swift ChatterboxMobile/MobilePDFCache.swift tests/pdf-cache/main.swift -o "$artifacts/test"
"$artifacts/test"
echo "PDF cache artifacts: $artifacts"
