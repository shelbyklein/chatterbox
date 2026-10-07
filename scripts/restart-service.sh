#!/bin/bash
# Restarts the background service (chatterboxd) so a newly installed build takes effect.
# Installing the app replaces the file but leaves the old service running.
#
#   scripts/restart-service.sh            wait until no chat is mid-reply, then restart
#   scripts/restart-service.sh --now      restart right away (replies in progress stop;
#                                         their chats keep their history)
#   scripts/restart-service.sh --app      also quit and reopen Chatterbox afterwards
#   scripts/restart-service.sh --delay N  start N seconds from now (so a chat's reply lands first)
#
# Runs detached and replaces any restart already queued, so restarts never stack up.
# The outcome goes to ~/Library/Application Support/Chatterbox/Diagnostics/service-restart.txt.
set -uo pipefail
sup="$HOME/Library/Application Support/Chatterbox"
report="$sup/Diagnostics/service-restart.txt"
lock="$sup/Diagnostics/service-restart.pid"

if [[ "${RESTART_SERVICE_DETACHED:-}" != 1 ]]; then
  # Replace an earlier queued restart, then carry on in the background.
  if [[ -f "$lock" ]] && old=$(cat "$lock") && kill -0 "$old" 2>/dev/null; then
    pkill -P "$old" 2>/dev/null; kill "$old" 2>/dev/null && echo "Replaced the restart queued earlier (pid $old)."
  fi
  RESTART_SERVICE_DETACHED=1 nohup "$0" "$@" >/dev/null 2>&1 &
  echo $! > "$lock"
  echo "Queued; the result goes to $report"
  exit 0
fi

now=0 app=0 delay=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --now) now=1 ;;
    --app) app=1 ;;
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
