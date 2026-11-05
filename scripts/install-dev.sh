#!/bin/bash
# Builds Chatterbox Dev from this checkout and installs it beside the real Chatterbox
# (plans/dev-environment.md): /Applications/Chatterbox Dev.app, its own service
# (com.shelbyklein.chatterboxd.dev), host, data (Application Support/Chatterbox Dev) and ports.
# The real app, its service, data and ~/.local/bin links are never touched.
#
#   scripts/install-dev.sh          build, install, restart Dev's service once its replies
#                                   finish (scripts/restart-service.sh --dev), reopen Dev's app
#   scripts/install-dev.sh --now    restart Dev's service right away
#   scripts/install-dev.sh --no-open   leave Dev's app closed
set -euo pipefail
cd "$(dirname "$0")/.."
# A few builds at a time across worktrees (by the Mac's pressure); xcodebuild waits for a slot (AGENTS.md).
source scripts/lib/build-lock.sh
now=0 reopen=1
for arg in "$@"; do
  case "$arg" in
    --now) now=1 ;;
    --no-open) reopen=0 ;;
    *) echo "Unknown option $arg" >&2; exit 2 ;;
  esac
done

NAME="Chatterbox Dev"
APP_ID=com.shelbyklein.Chatterbox.dev
LABEL=com.shelbyklein.chatterboxd.dev
DAEMON=chatterboxd-dev
APP="/Applications/$NAME.app"
BUILD="build/DerivedData-Dev/Build/Products/Dev/$NAME.app"
DATA="$HOME/Library/Application Support/$NAME"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
domain="gui/$(id -u)"

# Build first, so what's installed is always the current code.
xcodebuild -project Chatterbox.xcodeproj -scheme Chatterbox -configuration Dev \
  -derivedDataPath build/DerivedData-Dev build -quiet
[[ -d "$BUILD" ]] || { echo "No build at $BUILD." >&2; exit 1; }

# Only a Dev build goes in: every identity must be Dev's, or nothing is installed.
signed_id() { codesign -dv "$1" 2>&1 | sed -n 's/^Identifier=//p'; }
check() {  # check WHAT ACTUAL EXPECTED
  [[ "$2" == "$3" ]] || { echo "Not a Chatterbox Dev build ($1 is '$2', not '$3'); nothing installed." >&2; exit 1; }
}
check "the app's flavor" "$(/usr/libexec/PlistBuddy -c 'Print ChatterboxFlavor' "$BUILD/Contents/Info.plist")" dev
check "the app's id" "$(signed_id "$BUILD")" "$APP_ID"
check "the service's id" "$(signed_id "$BUILD/Contents/MacOS/$DAEMON")" "$APP_ID.Daemon"
check "the host's id" "$(signed_id "$BUILD/Contents/Helpers/ChatterboxHost.app")" "$APP_ID.Host"
check "the host's flavor" "$(/usr/libexec/PlistBuddy -c 'Print ChatterboxFlavor' "$BUILD/Contents/Helpers/ChatterboxHost.app/Contents/Info.plist")" dev
[[ ! -e "$BUILD/Contents/MacOS/chatterboxd" ]] || check "the service's name" chatterboxd "$DAEMON"
codesign --verify --deep --strict "$BUILD" || { echo "The Dev build's signature doesn't check out; nothing installed." >&2; exit 1; }

# Quit only Chatterbox Dev (by its own bundle id; `tell application id` would launch it if it
# weren't running, so only when it is).
if pgrep -xq "$NAME"; then
  osascript -e "tell application id \"$APP_ID\" to quit" 2>/dev/null || true
  for _ in {1..40}; do pgrep -xq "$NAME" || break; sleep 0.25; done
fi

# Replace the bundle outright: copying over an existing one can leave stale files that break
# its signature. A running Dev service keeps its old copy until it restarts below.
rm -rf "$APP"
ditto "$BUILD" "$APP"
codesign --verify --deep --strict "$APP"

# Dev's service LaunchAgent: the real one's shape, with Dev's program, folders and log.
mkdir -p "$DATA/Host" "$HOME/Library/LaunchAgents"
new_agent=$(mktemp "build/DerivedData-Dev/launchagent.XXXXXX")
/usr/bin/python3 -I - "$new_agent" "$LABEL" "$APP" "$DAEMON" "$DATA" <<'PY'
import plistlib, sys
out, label, app, daemon, data = sys.argv[1:]
plistlib.dump({
    'Label': label,
    'ProgramArguments': [f'{app}/Contents/MacOS/{daemon}'],
    'EnvironmentVariables': {
        'CHATTERBOX_DATA_DIR': data,
        'CHATTERBOX_HOST_DIR': f'{data}/Host',
        'CHATTERBOX_HOST_BINARY': f'{app}/Contents/Helpers/ChatterboxHost.app/Contents/MacOS/ChatterboxHost',
    },
    'KeepAlive': {'SuccessfulExit': False},
    'ProcessType': 'Background',
    'RunAtLoad': True,
    'StandardErrorPath': f'{data}/chatterboxd.log',
    'StandardOutPath': f'{data}/chatterboxd.log',
    'ThrottleInterval': 30,
}, open(out, 'wb'))
PY
loaded=0; launchctl print "$domain/$LABEL" >/dev/null 2>&1 && loaded=1
if cmp -s "$new_agent" "$AGENT" && (( loaded )); then
  rm -f "$new_agent"
  # Same service setup: restart it on the new build, after its replies finish unless --now.
  if (( now )); then ./scripts/restart-service.sh --dev --now; else ./scripts/restart-service.sh --dev; fi
else
  mv "$new_agent" "$AGENT"
  if (( loaded )); then
    echo "Dev's service setup changed; reloading $LABEL."
    launchctl bootout "$domain/$LABEL" 2>/dev/null || true
    for _ in {1..40}; do launchctl print "$domain/$LABEL" >/dev/null 2>&1 || break; sleep 0.25; done
  fi
  launchctl bootstrap "$domain" "$AGENT"
  echo "Started Dev's service ($LABEL)."
fi

if (( reopen )); then
  # Chats' shells carry their service's CHATTERBOX_* variables, and `open` would hand them to
  # the app. Dev's app finds its own folder from how it was built; launch it with none of them.
  unset_vars=()
  while IFS= read -r var; do [[ -n "$var" ]] && unset_vars+=(-u "$var"); done < <(env | sed -n 's/^\(CHATTERBOX_[A-Z_]*\)=.*/\1/p')
  env ${unset_vars[@]+"${unset_vars[@]}"} open "$APP"
  echo "Installed and opened $NAME."
else
  echo "Installed $NAME."
fi
