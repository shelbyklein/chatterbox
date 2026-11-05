#!/bin/bash
# The service answers within seconds of starting even when the background host doesn't (one
# that's stuck, or had just handed off to a newer one), and a reply the host couldn't confirm
# isn't marked lost: it's reattached once the host answers.
#
# A real service (build/runtime/chatterboxd, built here) and host, with the fake provider:
#   1. a Claude chat is mid-reply, waiting on an approval card; the service stops;
#   2. the host is frozen (SIGSTOP): it still accepts connections, but never answers;
#   3. a new service must be ready (daemon.sock, health "starting") within 10 s, with the
#      chat's approval still pending;
#   4. the host is let go (SIGCONT): the service reattaches the chat (running again), and
#      approving the card finishes the reply.
# STALLED_HOST_REUSE_DAEMON=1 skips rebuilding build/runtime/chatterboxd.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/chatterbox-test-stalled-host.XXXXXX)
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_TEST_TRUST_UI=1 CHATTERBOX_TEST_DISABLE_COMPUTER=1
export CHATTERBOX_PREFERENCES_SUITE="com.shelbyklein.Chatterbox.stalled-host-test.$RANDOM.$$"
export CHATTERBOX_COMPANION_PORT=0 CHATTERBOX_HOST_NOTIFY=0
export CHATTERBOX_HOST_IDLE_SECONDS=1000 CHATTERBOX_HOST_DETACHED_IDLE_SECONDS=1000
export FAKE_PROVIDER="$PWD/tests/fixtures/fake-provider.py"
mkdir -p "$CHATTERBOX_DATA_DIR" "$task_dir/bin"
# Their own copies, so the processes found below are this run's (and cleanup stops them).
cp -R build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/Helpers/ChatterboxHost.app "$task_dir/bin/"
export CHATTERBOX_HOST_BINARY="$task_dir/bin/ChatterboxHost.app/Contents/MacOS/ChatterboxHost"
[[ "${STALLED_HOST_REUSE_DAEMON:-0}" == 1 ]] || ./scripts/build-chatterbox-daemon.sh
cp build/runtime/chatterboxd "$task_dir/bin/chatterboxd"
host_pid=''
trap '[[ -n "$host_pid" ]] && kill -CONT "$host_pid" 2>/dev/null; defaults delete "$CHATTERBOX_PREFERENCES_SUITE" >/dev/null 2>&1 || true; echo "Stalled-host artifacts: $task_dir"' EXIT

fail() { echo "FAIL $*"; echo "--- service log"; tail -30 "$task_dir"/daemon*.log; exit 1; }

# One request to the service: call.py OPERATION JSON-BODY → the result as JSON.
cat > "$task_dir/call.py" <<'PY'
import json, os, socket, sys, uuid
s = socket.socket(socket.AF_UNIX); s.settimeout(float(os.environ.get('CALL_TIMEOUT', '5')))
s.connect(os.environ['CHATTERBOX_DATA_DIR'] + '/daemon.sock'); f = s.makefile('rwb')
def call(op, body):
    rid = str(uuid.uuid4())
    f.write((json.dumps({'version': 1, 'id': rid, 'operation': op, 'body': body}) + '\n').encode()); f.flush()
    while True:
        reply = json.loads(f.readline())
        if reply.get('id') == rid:
            if reply.get('error'): sys.exit('error: ' + reply['error'])
            return reply.get('result')
call('hello', {'role': 'ui'})   # Accepted only by an explicitly isolated test service.
print(json.dumps(call(sys.argv[1], json.loads(sys.argv[2]) if len(sys.argv) > 2 else {})))
PY
call() { /usr/bin/python3 "$task_dir/call.py" "$@"; }
chat_state() {   # running pending-approvals
  call get "{\"chatID\":\"$chat\"}" | /usr/bin/python3 -c '
import json,sys; c=json.load(sys.stdin)
print(str(c["running"]).lower(), sum(1 for i in c["record"]["items"] if i.get("approvalState")=="pending"))'
}
start_service() {
  "$task_dir/bin/chatterboxd" > "$task_dir/daemon$1.log" 2>&1 &
  daemon_pid=$!
}
chat_is() { [[ "$(chat_state 2>/dev/null)" == "$1" ]]; }
service_ready_within() {   # seconds → prints the health state once it answers
  local deadline=$(( $(date +%s) + $1 )) state
  while (( $(date +%s) < deadline )); do
    if state=$(CALL_TIMEOUT=2 call health 2>/dev/null); then
      /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("state","ready"))' <<< "$state"; return 0
    fi
    sleep 0.2
  done
  return 1
}
wait_for() {   # seconds description command…
  local deadline=$(( $(date +%s) + $1 )) what=$2; shift 2
  while (( $(date +%s) < deadline )); do "$@" && return 0; sleep 0.3; done
  fail "timed out: $what"
}

# 1. A reply in progress, waiting on an approval.
start_service 1
service_ready_within 15 >/dev/null || fail "first service never answered"
chat=$(uuidgen)
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
call create "{\"record\":{\"id\":\"$chat\",\"title\":\"Stalled host\",\"createdAt\":\"$now\",\"updatedAt\":\"$now\",\"model\":\"default\",\"effort\":\"\",\"personality\":\"neutral\",\"items\":[],\"activeBackend\":\"claude\"}}" >/dev/null
call send "{\"chatID\":\"$chat\",\"text\":\"needs approval\"}" >/dev/null
wait_for 20 "the reply asks for approval" chat_is 'true 1'
echo 'PASS a reply is mid-turn, waiting on an approval'
kill -TERM "$daemon_pid"; wait "$daemon_pid" 2>/dev/null || true
host_pid=$(pgrep -f "^$CHATTERBOX_HOST_BINARY\$" | head -1)
[[ -n "$host_pid" ]] || fail "no host running"
pgrep -P "$host_pid" >/dev/null || fail "the agent didn't outlive the service"

# 2. The host stops answering.
kill -STOP "$host_pid"
echo "PASS host $host_pid frozen: it accepts connections but never answers"

# 3. A new service answers anyway, and the chat isn't marked lost.
started=$(date +%s)
start_service 2
state=$(service_ready_within 10) || fail "the service didn't answer within 10 s of starting with a stuck host"
echo "PASS the service answered in $(( $(date +%s) - started )) s (health: $state)"
[[ "$state" == starting ]] || fail "health should say starting while the host doesn't answer (said $state)"
[[ "$(chat_state)" == 'false 1' ]] || fail "the chat should be reconnecting with its approval pending (got $(chat_state))"
echo 'PASS the unconfirmed chat keeps its pending approval (not settled as lost)'
# Past both tries (list timeout 5 s, a second on a new connection), still waiting, still not lost.
wait_for 20 "the service gives up on this round" grep -q "didn't confirm" "$task_dir/daemon2.log"
[[ "$(chat_state)" == 'false 1' ]] || fail "after the host didn't answer, the chat must still wait (got $(chat_state))"
grep -q "didn't answer within" "$task_dir/daemon2.log" || fail "no log line for the host not answering"
echo 'PASS after the host failed to answer twice, the chat still waits, and the log says why'

# 4. The host answers again: the reply is reattached and finishes.
kill -CONT "$host_pid"
wait_for 45 "the chat reattaches once the host answers" chat_is 'true 1'
echo 'PASS the reply is reattached once the host answers'
[[ "$(call health | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')" == ready ]] || fail "health should be ready now"
item=$(call get "{\"chatID\":\"$chat\"}" | /usr/bin/python3 -c '
import json,sys; print(next(i["id"] for i in json.load(sys.stdin)["record"]["items"] if i.get("approvalState")=="pending"))')
call approve "{\"chatID\":\"$chat\",\"itemID\":\"$item\",\"decision\":\"approved\"}" >/dev/null
wait_for 20 "the reply finishes" chat_is 'false 0'
echo 'PASS approving it finishes the reply in the reattached agent'
kill -TERM "$daemon_pid"; wait "$daemon_pid" 2>/dev/null || true
echo 'PASS service starts without waiting on a stuck host'
