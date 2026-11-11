#!/bin/bash
# Puts back the Chatterbox that the last real install replaced (scripts/install.sh, ship.sh
# keep it in build/previous), then restarts the real service between turns. Running it again
# goes forward again: the app it replaces is kept the same way.
#
#   scripts/rollback.sh          reopen the previous app and queue the service restart
#   scripts/rollback.sh --show   just say which builds are installed and kept
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/mac-install.sh
kept=build/previous/Chatterbox.app.zip
echo "Installed: $(cat build/previous/installed-commit 2>/dev/null || echo unknown)"
echo "Kept:      $( [[ -f $kept ]] && (cat build/previous/previous-commit 2>/dev/null || echo 'a build from before commits were recorded') || echo none)"
[[ "${1:-}" == --show ]] && exit 0
[[ -f "$kept" ]] || { echo "No previous build kept yet: it's saved on the next install." >&2; exit 1; }
restore=build/previous/restore
rm -rf "$restore"; mkdir -p "$restore"
ditto -x -k "$kept" "$restore"
[[ -d "$restore/Chatterbox.app" ]] || { echo "The kept build is damaged." >&2; exit 1; }
codesign --verify --deep --strict "$restore/Chatterbox.app"
# Install it like a build, then remove the unpacked copy (macOS would offer it as Chatterbox).
BUILD="$restore/Chatterbox.app" MAC_INSTALL_COMMIT="$(cat build/previous/previous-commit 2>/dev/null || echo 'a kept build')" \
  mac_install_bundle
rm -rf "$restore"
scripts/restart-service.sh
echo "Rolled back. Running it again goes forward to the build it replaced."
