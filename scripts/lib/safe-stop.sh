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
  local found
  found=$(hosted_work "$1")
  if [[ -n "$found" ]]; then
    printf 'Not stopping %s: it is running chat work:\n%s\n' "$1" "$found" >&2
    return 1
  fi
  local pids
  pids=$(_safe_tree "$1")
  kill $pids 2>/dev/null || true
  sleep 0.5
  kill -9 $pids 2>/dev/null || true
}
