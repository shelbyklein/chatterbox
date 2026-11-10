# Shared real-Mac delivery steps; sourced by the Bash delivery entry points.
# Caller holds the DerivedData lock through build, publication and bundle copy.
MAC_DERIVED_DATA=build/DerivedData
BUILD="$MAC_DERIVED_DATA/Build/Products/Debug/Chatterbox.app"
mac_build() {
  xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -configuration Debug \
    -derivedDataPath "$MAC_DERIVED_DATA" build -quiet
  [[ -d "$BUILD" ]] || { echo "No build at $BUILD." >&2; return 1; }
  codesign --verify --deep --strict "$BUILD"
}

mac_install_bundle() {
  osascript -e 'tell application "Chatterbox" to quit' 2>/dev/null || true
  for i in {1..20}; do pgrep -xq Chatterbox || break; sleep 0.25; done

  rm -rf /Applications/Chatterbox.app
  ditto "$BUILD" /Applications/Chatterbox.app
  codesign --verify --deep --strict /Applications/Chatterbox.app
  # Chats' agents publish web snippets with `snippet` (bin/snippet), from their shell's PATH.
  mkdir -p "$HOME/.local/bin"
  ln -sf /Applications/Chatterbox.app/Contents/Resources/bin/snippet "$HOME/.local/bin/snippet"
  # …and hand tasks to the other agent with `sidequest` (bin/sidequest).
  ln -sf /Applications/Chatterbox.app/Contents/Resources/bin/sidequest "$HOME/.local/bin/sidequest"
  # …and send work to Shelby-PC with `pc-errand` (the same script, by its other name).
  ln -sf /Applications/Chatterbox.app/Contents/Resources/bin/pc-errand "$HOME/.local/bin/pc-errand"
  # …and put work on the Desk with `desk` (bin/desk), for Shelby to place and start.
  ln -sf /Applications/Chatterbox.app/Contents/Resources/bin/desk "$HOME/.local/bin/desk"
  # …and start work threads from a front thread with `work` (bin/work, plans/work-threads.md).
  ln -sf /Applications/Chatterbox.app/Contents/Resources/bin/work "$HOME/.local/bin/work"
  # …and file and read a project's internal issues with `issue` (bin/issue, plans/project-issues.md).
  ln -sf /Applications/Chatterbox.app/Contents/Resources/bin/issue "$HOME/.local/bin/issue"
  # Chats' shells carry the background service's environment (CHATTERBOX_DATA_DIR and friends),
  # and `open` hands the caller's environment to the app. Launch it without any of them.
  clean_open() {
    local name unset_vars=()
    for name in ${!CHATTERBOX_@}; do unset_vars+=(-u "$name"); done
    env ${unset_vars[@]+"${unset_vars[@]}"} open "$@"
  }
  if (( $# )); then
    clean_open /Applications/Chatterbox.app --args "$@"
  else
    clean_open /Applications/Chatterbox.app
  fi
  echo "Installed and opened Chatterbox."
}
