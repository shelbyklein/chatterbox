#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/safe-stop.sh
fixture=$(mktemp -d /tmp/chatterbox-host-handoff.XXXXXX)
export CHATTERBOX_HOST_DIR="$fixture/host" CHATTERBOX_HOST_IDLE_SECONDS=1000 CHATTERBOX_HOST_NOTIFY=0
host_binary="$PWD/build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/Helpers/ChatterboxHost.app/Contents/MacOS/ChatterboxHost"
"$host_binary" > "$fixture/host.log" 2>&1 &
host_pid=$!
for attempt in {1..30}; do [[ -S "$CHATTERBOX_HOST_DIR/host.sock" ]] && break; sleep 0.1; done
python3 - <<'PY'
import socket,json,os
s=socket.socket(socket.AF_UNIX);s.connect(os.environ['CHATTERBOX_HOST_DIR']+'/host.sock')
s.sendall((json.dumps({'op':'spawn','id':'handoff-test','executable':'/bin/sleep','args':['1000']})+'\n').encode())
assert json.loads(s.makefile().readline())['op']=='spawned'
PY
if safe_stop "$host_pid" --idle-host; then echo 'FAIL stopped an occupied host'; exit 1; fi
kill -0 "$host_pid"
pgrep -P "$host_pid" >/dev/null
echo 'PASS occupied host and child remain alive'
python3 - <<'PY'
import socket,json,os
s=socket.socket(socket.AF_UNIX);s.connect(os.environ['CHATTERBOX_HOST_DIR']+'/host.sock')
s.sendall((json.dumps({'op':'kill','id':'handoff-test','forget':True})+'\n').encode())
PY
for attempt in {1..50}; do pgrep -P "$host_pid" >/dev/null || break; sleep 0.1; done
safe_stop "$host_pid" --idle-host
if kill -0 "$host_pid" 2>/dev/null; then echo 'FAIL empty host survived'; exit 1; fi
echo 'PASS explicitly approved empty host retired'
