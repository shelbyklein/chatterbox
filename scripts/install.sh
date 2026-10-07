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
# Chats' agents publish web snippets with `snippet` (bin/snippet), from their shell's PATH.
mkdir -p "$HOME/.local/bin"
ln -sf /Applications/Chatterbox.app/Contents/Resources/bin/snippet "$HOME/.local/bin/snippet"
# Chats' shells carry the background service's environment (CHATTERBOX_DATA_DIR and friends),
# and `open` hands the caller's environment to the app. Launch it without any of them.
clean_open() {
  local -a unset_vars
  for name in ${(k)parameters[(I)CHATTERBOX_*]}; do unset_vars+=(-u "$name"); done
  env "${unset_vars[@]}" open "$@"
}
if (( $# )); then
  clean_open /Applications/Chatterbox.app --args "$@"
else
  clean_open /Applications/Chatterbox.app
fi
echo "Installed and opened Chatterbox."
