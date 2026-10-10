#!/bin/bash
# Restarts the background service (chatterboxd) so a newly installed build takes effect.
# Installing the app replaces the file but leaves the old service running.
#
#   scripts/restart-service.sh            wait until no chat is mid-reply, then restart
#   scripts/restart-service.sh --now      restart right away (replies in progress stop;
#                                         their chats keep their history)
#   scripts/restart-service.sh --app      also quit and reopen Chatterbox afterwards
#   scripts/restart-service.sh --codex    also stop Chatterbox's Codex process (only the one
#                                         under its host, never the ChatGPT app's), so the next
#                                         Codex chat starts it fresh with current settings
#   scripts/restart-service.sh --delay N  start N seconds from now (so a chat's reply lands first)
#
# Runs detached and replaces any restart already queued, so restarts never stack up.
# The outcome goes to ~/Library/Application Support/Chatterbox/Diagnostics/service-restart.txt.
set -uo pipefail
sup="$HOME/Library/Application Support/Chatterbox"
report="$sup/Diagnostics/service-restart.txt"
lock="$sup/Diagnostics/service-restart.pid"
queue_label="com.shelbyklein.chatterbox.restart-service"
mkdir -p "$sup/Diagnostics" || exit 1

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

now=0 app=0 codex=0 delay=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --now) now=1 ;;
    --app) app=1 ;;
    --codex) codex=1 ;;
    --delay) delay=${2:-0}; shift ;;
  esac
  shift
done
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$report"; }
cleanup() { [[ "$(cat "$lock" 2>/dev/null)" == $$ ]] && rm -f "$lock"; }
trap cleanup EXIT

# How many chats are mid-reply, from the service's local API ("err" if it doesn't answer).
running() {
  curl -s -m 10 -H "x-chatterbox-token: $(cat "$sup/agent-token")" http://127.0.0.1:47320/v1/chats \
    | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(c["isRunning"] for g in d["groups"] for c in g["chats"]))' 2>/dev/null \
    || echo err
}

sleep "$delay"
if (( ! now )); then
  log "waiting for every chat to finish its reply"
  deadline=$(( $(date +%s) + 4*3600 ))
  while true; do
    if (( $(date +%s) > deadline )); then log "gave up after 4 hours: replies still running; no restart"; exit 1; fi
    a=$(running); sleep 15; b=$(running)
    [[ "$a" == 0 && "$b" == 0 ]] && break
    sleep 15
  done
fi

old=$(pgrep -x chatterboxd)
log "restarting chatterboxd (was pid ${old:-none})"
launchctl kickstart -k "gui/$(id -u)/com.shelbyklein.chatterboxd"
for _ in $(seq 60); do
  new=$(pgrep -x chatterboxd); [[ -n "$new" && "$new" != "$old" ]] && break; sleep 1
done
if (( codex )); then
  # Chatterbox keeps one Codex app-server in its host and reattaches to it across restarts,
  # so a changed launch setting only applies to a fresh one. Chats keep their threads.
  for host in $(pgrep -f "Chatterbox.app/Contents/MacOS/ChatterboxHost"); do
    for pid in $(pgrep -P "$host" -f "codex app-server"); do
      log "stopping Chatterbox's Codex app-server (pid $pid)"
      kill "$pid" 2>/dev/null
    done
  done
fi
if (( app )); then
  osascript -e 'tell application "Chatterbox" to quit' 2>/dev/null
  for _ in $(seq 40); do pgrep -xq Chatterbox || break; sleep 0.5; done
  # Agent shells carry the service's CHATTERBOX_* variables; the app must not inherit them.
  env $(env | sed -n 's/^\(CHATTERBOX_[A-Z_]*\)=.*/-u \1/p') open /Applications/Chatterbox.app
fi
sleep 10
health=$(/usr/bin/python3 - <<'PY' 2>/dev/null || echo failed
import socket,json,uuid,os
s=socket.socket(socket.AF_UNIX); s.settimeout(20)
s.connect(os.path.expanduser('~/Library/Application Support/Chatterbox/daemon.sock')); f=s.makefile('rwb')
def call(op,b=None):
    k=str(uuid.uuid4()); f.write((json.dumps(dict(version=1,id=k,operation=op,body=b or {}))+'\n').encode()); f.flush()
    while True:
        r=json.loads(f.readline())
        if r.get('id')==k: return r
call('hello',{'role':'agent'}); print('ok' if 'result' in call('health') else 'failed')
PY
)
log "chatterboxd pid ${new:-none}, health ${health}; app pid $(pgrep -x Chatterbox || echo none)"
