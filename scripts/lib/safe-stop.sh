# Sourced by scripts that stop processes. Never stop a process blind: one that looks idle can
# be hosting live chats (an old ChatterboxHost carried 8 Claude chats when one was stopped).
#
#   hosted_work PID   prints any Claude, Codex or Chatterbox process at or under PID
#   safe_stop PID     stops PID and what it started, unless hosted_work finds something

_safe_tree() {
  local child
  printf '%s\n' "$1"
  for child in $(pgrep -P "$1" 2>/dev/null); do _safe_tree "$child"; done
}

hosted_work() {
  local pid
  for pid in $(_safe_tree "$1"); do
    ps -o pid=,command= -p "$pid" 2>/dev/null \
      | grep -E '(^|/)(claude|codex)( |$)|claude -p|app-server|ChatterboxHost|chatterboxd|chatterbox-mcp|/Chatterbox( |$)' \
      | grep -v fake-provider
  done
}

safe_stop() {
  local found idle_host_frozen=0
  # Explicitly authorized host handoff: only an empty ChatterboxHost may be stopped.
  # Never bypass the protection while it still owns any child process.
  if [[ "${2:-}" == --idle-host ]]; then
    if ! ps -o comm= -p "$1" | grep -Eq '/ChatterboxHost$'; then
      printf 'Not stopping %s: not a ChatterboxHost.\n' "$1" >&2; return 1
    fi
    if pgrep -P "$1" >/dev/null 2>&1; then
      printf 'Not stopping %s: agent processes remain.\n' "$1" >&2; return 1
    fi
    # Freeze the empty host for the final child check, so it cannot spawn between
    # that check and termination. If a child raced the first check, resume and refuse.
    kill -STOP "$1" 2>/dev/null || return 1
    idle_host_frozen=1
    if pgrep -P "$1" >/dev/null 2>&1; then
      kill -CONT "$1" 2>/dev/null || true
      printf 'Not stopping %s: an agent started during the idle check.\n' "$1" >&2
      return 1
    fi
    found=""
  else
    found=$(hosted_work "$1")
  fi
  if [[ -n "$found" ]]; then
    printf 'Not stopping %s: it is running chat work:\n%s\n' "$1" "$found" >&2
    return 1
  fi
  local pids
  pids=$(_safe_tree "$1")
  kill $pids 2>/dev/null || true
  (( idle_host_frozen )) && kill -CONT "$1" 2>/dev/null || true
  sleep 0.5
  kill -9 $pids 2>/dev/null || true
}
