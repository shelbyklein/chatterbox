#!/bin/bash
# Build, commit staged work, push main, then install and restart the Mac app.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(git branch --show-current)" != main ]]; then
  echo "Run ship.sh from main after reconciling feature work." >&2
  exit 1
fi
if ! git diff --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo "Review and stage the changes you want to ship first (git add <files>)." >&2
  exit 1
fi
if ! git diff --cached --quiet && [[ -z "${1:-}" ]]; then
  echo 'Staged changes require a commit message: ./scripts/ship.sh "Describe the change"' >&2
  exit 1
fi
xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -configuration Debug \
  -derivedDataPath build/DerivedData build -quiet
if ! git diff --cached --quiet; then
  git commit -m "$1"
fi
git push origin main
./scripts/install.sh
# Confirm the installed executable matches the build and has reopened.
cmp build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/MacOS/Chatterbox \
  /Applications/Chatterbox.app/Contents/MacOS/Chatterbox
for attempt in {1..20}; do
  if ps -axo comm= | grep -Fx /Applications/Chatterbox.app/Contents/MacOS/Chatterbox >/dev/null; then
    echo "Shipped $(git rev-parse --short HEAD): pushed, installed and running."
    exit 0
  fi
  sleep 0.5
done
echo "Installed, but Chatterbox did not reopen. Check Diagnostics before retrying." >&2
exit 1
