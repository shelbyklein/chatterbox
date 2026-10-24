# check_embedded APP: every @rpath framework the app's binary links must be inside the app.
# Simulator tests don't catch a missing one (Xcode adds the build folder to the search path),
# but a phone stops at launch with "Library missing".
check_embedded() {
  local app=$1 missing=0 binaries
  # The app's binary, and in Debug builds the .debug.dylib that holds its code.
  binaries=("$app/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Info.plist")")
  for dylib in "$app"/*.dylib; do [[ -f "$dylib" ]] && binaries+=("$dylib"); done
  for framework in $(for b in "${binaries[@]}"; do otool -L "$b"; done | awk '/@rpath\/.*\.framework/ {print $1}' | sed 's|@rpath/||; s|/.*||' | sort -u); do
    if [[ ! -d "$app/Frameworks/$framework" ]]; then
      echo "Not inside the app: $framework (it would crash at launch). Embed it in project.yml." >&2
      missing=1
    fi
  done
  return $missing
}
