#!/bin/bash
# Installing a newer host build hands off without stopping anything: see tests/host-handoff.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/source-list.sh
task_dir=$(mktemp -d /tmp/chatterbox-host-upgrade.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_HOST_NOTIFY=0 CHATTERBOX_HOST_IDLE_SECONDS=2 CHATTERBOX_HOST_DETACHED_IDLE_SECONDS=1000
built="$PWD/build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/Helpers/ChatterboxHost.app"
# The "older build": the same host at another path, so the current build looks different.
mkdir -p "$CHATTERBOX_DATA_DIR" "$task_dir/old" "$task_dir/new"
cp -R "$built" "$task_dir/old/ChatterboxHost.app"
cp -R "$built" "$task_dir/new/ChatterboxHost.app"
export OLD_HOST="$task_dir/old/ChatterboxHost.app/Contents/MacOS/ChatterboxHost"
# --legacy: the older build is the host from before handoffs (it answers "Unknown request",
# locks host.lock, and removes host.sock when it exits), built from the last commit.
if [[ "${1:-}" == --legacy ]]; then
  mkdir -p "$task_dir/legacy-src"
  for f in main Host Child OutputBuffer Watcher; do git show "${LEGACY_REV:-HEAD}:ChatterboxHost/$f.swift" > "$task_dir/legacy-src/$f.swift"; done
  git -C Core show "${LEGACY_CORE_REV:-HEAD}:Chatterbox/Support/JSON.swift" > "$task_dir/legacy-src/JSON.swift"
  git -C Core show "${LEGACY_CORE_REV:-HEAD}:Chatterbox/Support/HostProtocol.swift" > "$task_dir/legacy-src/HostProtocol.swift" 2>/dev/null \
    || cp Core/Chatterbox/Support/HostProtocol.swift "$task_dir/legacy-src/"
  # Hosts since Chatterbox Dev read their folder from Flavor.swift; older ones have none.
  git -C Core show "${LEGACY_CORE_REV:-HEAD}:Shared/Flavor.swift" > "$task_dir/legacy-src/Flavor.swift" 2>/dev/null \
    || rm -f "$task_dir/legacy-src/Flavor.swift"
  OLD_HOST="$task_dir/old/legacy-host"
  swiftc -O -o "$OLD_HOST" "$task_dir"/legacy-src/*.swift
  touch -t "$(date -v-1d +%Y%m%d%H%M)" "$OLD_HOST"
fi
export CHATTERBOX_HOST_BINARY="$task_dir/new/ChatterboxHost.app/Contents/MacOS/ChatterboxHost"
# Compiled before the old host starts: waiting for the build slot can take longer than the
# old host's process lives.
./scripts/runtime-sources.sh > "$task_dir/sources"
check_source_list "$task_dir/sources"
cp tests/host-handoff/main.swift "$task_dir/main.swift"
swiftc -D CHATTERBOX_HEADLESS -whole-module-optimization -Onone -o "$task_dir/test" @"$task_dir/sources" "$task_dir/main.swift"
# The older build was written a day earlier.
touch -t "$(date -v-1d +%Y%m%d%H%M)" "$OLD_HOST"
"$OLD_HOST" > "$task_dir/old.log" 2>&1 &
for _ in {1..50}; do [[ -S "$CHATTERBOX_HOST_DIR/host.sock" ]] && break; sleep 0.1; done
python3 - <<'PY'
import socket,json,os
s=socket.socket(socket.AF_UNIX);s.connect(os.environ['CHATTERBOX_HOST_DIR']+'/host.sock')
s.sendall((json.dumps({'op':'spawn','id':'before-install','executable':'/bin/sleep','args':['300']})+'\n').encode())
assert json.loads(s.makefile().readline())['op']=='spawned'
PY
"$task_dir/test"
pkill -f "$task_dir/" 2>/dev/null || true
for _ in {1..50}; do pgrep -f "$task_dir/(old|new)/" >/dev/null || break; sleep 0.1; done
[[ "${1:-}" == --legacy ]] && exit 0

# An idle older host (nothing running): the client's list must be answered at once even
# though the old host is let go right after it's moved aside (tests/host-handoff idleHandoff).
rm -rf "$CHATTERBOX_HOST_DIR"
CHATTERBOX_HOST_IDLE_SECONDS=1000 "$OLD_HOST" > "$task_dir/old-idle.log" 2>&1 &
for _ in {1..50}; do [[ -S "$CHATTERBOX_HOST_DIR/host.sock" ]] && break; sleep 0.1; done
CHATTERBOX_HOST_IDLE_SECONDS=1000 HANDOFF_IDLE=1 "$task_dir/test"
pkill -f "$task_dir/" 2>/dev/null || true
