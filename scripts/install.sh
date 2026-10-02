#!/bin/zsh
# Builds the app, installs it into /Applications, and opens it.
# Replaces the app bundle outright: copying over an existing bundle can leave stale
# files that break its code signature, and macOS then refuses to launch it.
set -e
cd "$(dirname "$0")/.."
BUILD="build/DerivedData/Build/Products/Debug/Chatterbox.app"
# Build first, so what's installed is always the current code.
xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -configuration Debug \
  -derivedDataPath build/DerivedData build -quiet
[ -d "$BUILD" ] || { echo "No build at $BUILD."; exit 1; }

osascript -e 'tell application "Chatterbox" to quit' 2>/dev/null || true
for i in {1..20}; do pgrep -xq Chatterbox || break; sleep 0.25; done

rm -rf /Applications/Chatterbox.app
ditto "$BUILD" /Applications/Chatterbox.app
codesign --verify --deep --strict /Applications/Chatterbox.app
if (( $# )); then
  open /Applications/Chatterbox.app --args "$@"
else
  open /Applications/Chatterbox.app
fi
echo "Installed and opened Chatterbox."
