#!/bin/bash
# Runs a long job in its own session, so it survives the agent session that started it ending
# (test suites, freeze hunts). Output and the exit code land in build/runs/:
#
#   scripts/detach.sh NAME CMD…     start it; prints where its log and status go
#   build/runs/NAME.log             everything it prints
#   build/runs/NAME.status          "running PID", then "exit N" when it ends
#
# Watch for the end with:  until grep -q '^exit' build/runs/NAME.status; do sleep 5; done
# A NAME already running is refused, so a retry doesn't start a second copy.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# -ge 2 ]] || { echo "Usage: scripts/detach.sh NAME CMD…" >&2; exit 2; }
name=$1; shift
[[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "NAME: letters, digits, . _ - only" >&2; exit 2; }
mkdir -p build/runs
log="build/runs/$name.log" status="build/runs/$name.status"
if [[ -f "$status" ]] && read -r state pid < "$status" && [[ "$state" == running ]] && kill -0 "$pid" 2>/dev/null; then
  echo "$name is already running (pid $pid); its log: $log" >&2; exit 1
fi
# A new session (setsid) and a double fork: no controlling terminal or parent to take it down.
/usr/bin/python3 -I - "$log" "$status" "$@" <<'PY'
import os, sys
log, status, cmd = sys.argv[1], sys.argv[2], sys.argv[3:]
if os.fork(): os._exit(0)
os.setsid()
if os.fork(): os._exit(0)
fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
os.dup2(fd, 1); os.dup2(fd, 2)
os.dup2(os.open(os.devnull, os.O_RDONLY), 0)
open(status, 'w').write(f'running {os.getpid()}\n')
pid = os.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
_, st = os.waitpid(pid, 0)
open(status, 'w').write(f'exit {os.waitstatus_to_exitcode(st)}\n')
PY
sleep 0.3
echo "Started $name. Log: $log  Status: $status"
