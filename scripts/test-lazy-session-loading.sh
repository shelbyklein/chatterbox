#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/golem-lazy-loading.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_DAEMON_CLIENT=1 CHATTERBOX_TEST_TRUST_UI=1 CHATTERBOX_TEST_DISABLE_COMPUTER=1
export CHATTERBOX_PREFERENCES_SUITE="com.shelbyklein.Chatterbox.lazy-test.$RANDOM.$$"
export CHATTERBOX_AGENT_PORT=0 CHATTERBOX_COMPANION_PORT=0
export CHATTERBOX_HOST_NOTIFY=0
export CHATTERBOX_HOST_BINARY="$PWD/build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/Helpers/ChatterboxHost.app/Contents/MacOS/ChatterboxHost"
export CHATTERBOX_HOST_IDLE_SECONDS=1 CHATTERBOX_HOST_DETACHED_IDLE_SECONDS=1
export FAKE_PROVIDER="$PWD/tests/golem-integration/fake-provider.py"
export LAZY_CAPTURE="${LAZY_CAPTURE:-$PWD/design/lazy-session-loading/selected-chat.png}"
mkdir -p design/lazy-session-loading
products=build/DerivedData/Build/Products/Debug
mkdir -p "$products"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name ChatterboxApp.swift > "$task_dir/sources"
if [[ "${LAZY_TEST_REUSE_BINARY:-0}" != 1 ]]; then
  swiftc -I "$products" "$products/SwiftTerm.o" -D DEBUG -whole-module-optimization -Onone \
    -o "$products/lazy-session-loading-tests" @"$task_dir/sources" tests/lazy-session-loading/main.swift
fi
"$products/lazy-session-loading-tests" seed
build/runtime/chatterboxd > "$task_dir/daemon.log" 2>&1 &
daemon_pid=$!
trap 'echo "Lazy-loading artifacts: $task_dir"; defaults delete "$CHATTERBOX_PREFERENCES_SUITE" >/dev/null 2>&1 || true' EXIT
for attempt in {1..100}; do
  [[ -S "$CHATTERBOX_DATA_DIR/daemon.sock" ]] && break
  sleep 0.1
done
# The service correctly expires requests found on disk after an interrupted launch.
# Insert this owned test conversation after startup to exercise a live pending card.
/usr/bin/python3 - <<'PY'
import json, os, socket, uuid
from pathlib import Path
root = Path(os.environ['CHATTERBOX_DATA_DIR'])
chat_id = '10000000-0000-0000-0000-000000000001'
record = json.loads((root / 'Conversations' / (chat_id + '.json')).read_text())
for row in record['items']:
    row['text'] = row.get('text', '')[:500]
record['items'][20]['approvalState'] = 'pending'
record['items'][750]['text'] = '![Earlier render](' + str(root / 'fixture-render.png') + ')'
s = socket.socket(socket.AF_UNIX)
s.settimeout(20)
s.connect(str(root / 'daemon.sock'))
f = s.makefile('rwb')
def call(operation, body):
    request_id = str(uuid.uuid4())
    f.write((json.dumps(dict(version=1, id=request_id, operation=operation, body=body), separators=(',', ':')) + '\n').encode())
    f.flush()
    while True:
        reply = json.loads(f.readline())
        if reply.get('id') == request_id:
            assert 'error' not in reply, reply.get('error')
            return reply.get('result')
call('hello', {'role': 'ui'})  # Accepted only by this explicitly isolated test daemon.
call('delete', {'chatID': chat_id})
call('create', {'record': record})
PY
"$products/lazy-session-loading-tests"
