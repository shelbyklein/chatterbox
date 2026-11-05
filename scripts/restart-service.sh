#!/bin/bash
# Restarts the background service (chatterboxd) so a newly installed build takes effect.
# Installing the app replaces the file but leaves the old service running.
#
#   scripts/restart-service.sh            restart between turns: as soon as no reply has
#                                         produced anything for 3 s (hosts carry the agents
#                                         across the restart), at the latest after 20 min
#   scripts/restart-service.sh --now      restart right away
#   scripts/restart-service.sh --app      also quit and reopen Chatterbox afterwards
#   scripts/restart-service.sh --codex    also stop Chatterbox's Codex process (only the one
#                                         under its host, never the ChatGPT app's), so the next
#                                         Codex chat starts it fresh with current settings
#   scripts/restart-service.sh --host     (kept for old habits) hosts now hand off by themselves
#   scripts/restart-service.sh --delay N  start N seconds from now (so a chat's reply lands first)
#   scripts/restart-service.sh --dev      Chatterbox Dev's service (chatterboxd-dev) instead, and
#                                         with --app its app; the real one is left alone
#
# When it restarts (the rule that fired is in the report):
#   idle           no chat is mid-reply.
#   between turns  chats are mid-reply, but none has produced anything for RESTART_SERVICE_GAP
#                  seconds (3): the service is between steps of their replies. The agents
#                  themselves live in the background hosts (ChatterboxHost), which the service
#                  reattaches to when it comes back (see HostClient.connect and
#                  scripts/test-host-handoff.sh), so a reply carries on; the app reconnects.
#                  "Wait for every reply to finish" never fired once work threads ran all day.
#   cap            after RESTART_SERVICE_CAP seconds (20 min) of looking: at the next pause in
#                  the stream however short, and in any case RESTART_SERVICE_GRACE seconds
#                  (5 min) later.
#   unresponsive   the service hasn't answered its socket for 60 s.
#
# Runs detached and replaces any restart already queued, so restarts never stack up.
# The outcome goes to ~/Library/Application Support/Chatterbox/Diagnostics/service-restart.txt
# (Chatterbox Dev: Application Support/Chatterbox Dev/Diagnostics).
set -uo pipefail
dev=0
for arg in "$@"; do [[ "$arg" == --dev ]] && dev=1; done
if (( dev )); then
  name="Chatterbox Dev" app_id=com.shelbyklein.Chatterbox.dev daemon=chatterboxd-dev service=com.shelbyklein.chatterboxd.dev
  queue_label="com.shelbyklein.chatterbox.restart-service.dev"
else
  name=Chatterbox app_id=com.shelbyklein.Chatterbox daemon=chatterboxd service=com.shelbyklein.chatterboxd
  queue_label="com.shelbyklein.chatterbox.restart-service"
fi
sup=${RESTART_SERVICE_SUPPORT_DIR:-$HOME/Library/Application Support/$name}
report="$sup/Diagnostics/service-restart.txt"
lock="$sup/Diagnostics/service-restart.pid"
mkdir -p "$sup/Diagnostics" || exit 1
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$report"; }

# What the service says over its socket: "<chats mid-reply> <event sequence>", or "err" when it
# doesn't answer. The sequence goes up with every event a reply produces (output, a tool step,
# a saved record), so an unchanged sequence means no reply is mid-stream right now.
service_status() {
  /usr/bin/python3 - "$sup/daemon.sock" <<'PY' 2>/dev/null || echo err
import json, socket, sys, uuid
s = socket.socket(socket.AF_UNIX); s.settimeout(10); s.connect(sys.argv[1]); f = s.makefile("rwb")
def ask(op, body):
    rid = str(uuid.uuid4())
    f.write((json.dumps({"version": 1, "id": rid, "operation": op, "body": body}) + "\n").encode()); f.flush()
    while True:
        reply = json.loads(f.readline())
        if reply.get("id") == rid:
            if reply.get("error"): raise SystemExit(1)
            return reply.get("result")
ask("hello", {"role": "agent"})
# Only the working sessions, in short form: the full list can be too big to send.
running = sum(1 for c in ask("list", {"workingOnly": True, "summaryOnly": True}) or [] if c.get("running"))
print(running, int((ask("health", {}) or {}).get("sequence", 0)))
PY
}

# Waits for the moment to restart and prints the rule that fired (see the top of the file).
# RESTART_SERVICE_STATUS_CMD replaces service_status for tests.
wait_for_turn_gap() {
  local gap=${RESTART_SERVICE_GAP:-3} cap=${RESTART_SERVICE_CAP:-1200} grace=${RESTART_SERVICE_GRACE:-300} poll=${RESTART_SERVICE_POLL:-1}
  local started now status running sequence last_sequence='' quiet_since err_since=''
  started=$(date +%s); quiet_since=$started
  log "waiting for a gap between replies: restart once no reply has produced anything for ${gap}s, at the latest ${cap}s from now"
  while true; do
    now=$(date +%s)
    status=$(${RESTART_SERVICE_STATUS_CMD:-service_status})
    if [[ "$status" == err ]]; then
      : "${err_since:=$now}"
      if (( now - err_since >= ${RESTART_SERVICE_UNRESPONSIVE:-60} )); then echo unresponsive; return; fi
      sleep "$poll"; continue
    fi
    err_since=''
    running=${status%% *}; sequence=${status##* }
    if [[ "$running" == 0 ]]; then echo idle; return; fi
    if [[ "$sequence" != "$last_sequence" ]]; then last_sequence=$sequence; quiet_since=$now
    elif (( now - quiet_since >= gap )); then echo "between turns"; return; fi
    if (( now - started >= cap )); then
      if (( now - quiet_since >= poll )) || (( now - started >= cap + grace )); then echo cap; return; fi
    fi
    sleep "$poll"
  done
}
if [[ "${RESTART_SERVICE_WAIT_ONLY:-}" == 1 ]]; then wait_for_turn_gap; exit 0; fi

if [[ "${RESTART_SERVICE_DETACHED:-}" != 1 ]]; then
  # launchd owns the worker: nohup alone can still be reaped with an agent's shell.
  # Replace only this restart job; an old PID file may now refer to another process.
  launchctl remove "$queue_label" 2>/dev/null || true
  if [[ -f "$lock" ]] && old=$(cat "$lock") && kill -0 "$old" 2>/dev/null; then
    if ps -p "$old" -o command= | grep -Fq 'scripts/restart-service.sh'; then
      pkill -P "$old" 2>/dev/null; kill "$old" 2>/dev/null && echo "Replaced the restart queued earlier (pid $old)."
    fi
  fi
  worker="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  job="$sup/Diagnostics/service-restart.plist"
  /usr/bin/python3 - "$job" "$queue_label" "$worker" "$@" <<'PY' || exit 1
import plistlib,sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'Label':sys.argv[2], 'ProgramArguments':['/bin/bash',*sys.argv[3:]],
                  'EnvironmentVariables':{'RESTART_SERVICE_DETACHED':'1'},
                  'RunAtLoad':True, 'KeepAlive':False, 'ProcessType':'Background'}, f)
PY
  # Unlike `submit`, this is one-shot even if it times out or fails.
  launchctl bootstrap "gui/$(id -u)" "$job" || exit 1
  echo "Queued; the result goes to $report"
  exit 0
fi
echo $$ > "$lock"

now=0 app=0 codex=0 host_refresh=0 delay=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --now) now=1 ;;
    --app) app=1 ;;
    --codex) codex=1 ;;
    --host) host_refresh=1 ;;
    --delay) delay=${2:-0}; shift ;;
    --dev) ;;
  esac
  shift
done
cleanup() { [[ "$(cat "$lock" 2>/dev/null)" == $$ ]] && rm -f "$lock"; }
trap cleanup EXIT

sleep "$delay"
if (( now )); then
  rule="--now"
else
  rule=$(wait_for_turn_gap)
fi
log "restart rule: $rule"

old=$(pgrep -x "$daemon")
log "restarting $daemon (was pid ${old:-none})"
launchctl kickstart -k "gui/$(id -u)/$service"
for _ in $(seq 60); do
  new=$(pgrep -x "$daemon"); [[ -n "$new" && "$new" != "$old" ]] && break; sleep 1
done
if (( codex )); then
  # Chatterbox keeps one Codex app-server in its host and reattaches to it across restarts,
  # so a changed launch setting only applies to a fresh one. Chats keep their threads.
  for host in $(pgrep -f "$name.app/Contents/(MacOS|Helpers/ChatterboxHost.app/Contents/MacOS)/ChatterboxHost"); do
    for pid in $(pgrep -P "$host" -f "codex app-server"); do
      log "stopping Chatterbox's Codex app-server (pid $pid)"
      kill "$pid" 2>/dev/null
    done
  done
fi
if (( host_refresh )); then
  # Hosts hand off on their own: when the service or app connects and the running host is
  # from an older build, it's moved aside to finish its processes and a current one takes
  # new work (HostClient.connect). Nothing to stop here.
  log "host handoff: automatic once the service reconnects; an older host exits when its agents finish"
fi
if (( app )); then
  # By bundle id, so the other copy is never the one asked; only when it's running, since
  # `tell application id` would launch it first.
  pgrep -xq "$name" && osascript -e "tell application id \"$app_id\" to quit" 2>/dev/null
  for _ in $(seq 40); do pgrep -xq "$name" || break; sleep 0.5; done
  # Agent shells carry the service's CHATTERBOX_* variables; the app must not inherit them.
  env $(env | sed -n 's/^\(CHATTERBOX_[A-Z_]*\)=.*/-u \1/p') open "/Applications/$name.app"
fi
# The service listens as soon as it has loaded its chats; reattaching to the background host
# comes after ("starting" until then). Ask every second, for up to RESTART_SERVICE_HEALTH_WAIT
# seconds (60), and say how long it took.
health_check() {
  /usr/bin/python3 - "$sup/daemon.sock" <<'PY' 2>/dev/null || echo failed
import socket,json,uuid,sys
s=socket.socket(socket.AF_UNIX); s.settimeout(5)
s.connect(sys.argv[1]); f=s.makefile('rwb')
def call(op,b=None):
    k=str(uuid.uuid4()); f.write((json.dumps(dict(version=1,id=k,operation=op,body=b or {}))+'\n').encode()); f.flush()
    while True:
        r=json.loads(f.readline())
        if r.get('id')==k: return r
call('hello',{'role':'agent'}); r=call('health')
print(r['result'].get('state','ready') if 'result' in r else 'failed')
PY
}
health=failed waited=0 health_wait=${RESTART_SERVICE_HEALTH_WAIT:-60} health_start=$(date +%s)
while (( waited < health_wait )); do
  sleep 1
  health=$(health_check); waited=$(( $(date +%s) - health_start ))
  [[ "$health" == ready ]] && break
  # Answering but still reattaching: give that a little longer, then report it as such.
  [[ "$health" == starting ]] && (( waited >= 20 )) && break
done
case "$health" in
  ready) health="ok after ${waited}s" ;;
  starting) health="ok after ${waited}s, still reattaching chats to the background host" ;;
  *) health="failed (no answer in ${waited}s)" ;;
esac
log "$daemon pid ${new:-none}, health ${health}; app pid $(pgrep -x "$name" || echo none)"
