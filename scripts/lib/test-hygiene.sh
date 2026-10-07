# Sourced near the top of every scripts/test-*.sh (bash). Whatever a test run leaves behind
# goes away when it exits, pass or fail, so test runs don't pile up processes and app copies:
#
#  - processes the run started are stopped: its children, and anything still running from
#    its temp folders (fake providers and services outlive the scripts that start them);
#  - app bundles and Xcode build folders inside its temp folders are deleted, since each is a
#    full copy of Chatterbox that macOS then offers as an app. Logs and screenshots stay, so
#    renders can still be looked at; scripts/tidy.sh removes old temp folders later.
#
# The script's own `trap '…' EXIT` keeps working: this file runs it first, then cleans up.
# KEEP_TEST_BUILDS=1 keeps the app bundles too, for debugging a failed run.

# macOS runs these with bash 3.2: no BASHPID, and empty arrays trip `set -u`, hence the
# `${a[@]+…}` forms. Temp folders are recorded in a file, because `d=$(mktemp -d …)` runs
# mktemp in a subshell that can't add to an array here.
_hygiene_exit_cmds=()
_hygiene_list=$(command mktemp /tmp/test-hygiene.XXXXXX)

# Collect EXIT traps instead of letting each replace the last (or this file's).
trap() {
  local cmd=${1-} sig others=() exit_too=0
  [[ $# -ge 2 ]] || { builtin trap "$@"; return; }
  for sig in "${@:2}"; do
    if [[ "$sig" == EXIT || "$sig" == 0 ]]; then exit_too=1; else others+=("$sig"); fi
  done
  if (( exit_too )); then
    if [[ "$cmd" == - || -z "$cmd" ]]; then _hygiene_exit_cmds=(); else _hygiene_exit_cmds+=("$cmd"); fi
  fi
  if [[ ${#others[@]} -gt 0 ]]; then builtin trap "$cmd" "${others[@]}"; fi
  return 0
}

# Remember every temp folder the run makes.
mktemp() {
  local made
  made=$(command mktemp "$@") || return
  if [[ -d "$made" ]]; then printf '%s\n' "$made" >> "$_hygiene_list"; fi
  printf '%s\n' "$made"
}

_hygiene_descendants() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null); do
    _hygiene_descendants "$child"
    printf '%s\n' "$child"
  done
}

_hygiene_cleanup() {
  local status=$? cmd dir pids dirs
  builtin trap - EXIT
  set +eu
  for cmd in ${_hygiene_exit_cmds[@]+"${_hygiene_exit_cmds[@]}"}; do eval "$cmd" || true; done
  dirs=$(cat "$_hygiene_list" 2>/dev/null)
  pids=$(_hygiene_descendants $$)
  while IFS= read -r dir; do
    [[ -n "$dir" ]] && pids="$pids"$'\n'"$(pgrep -f -- "$dir" 2>/dev/null)"
  done <<< "$dirs"
  pids=$(printf '%s\n' "$pids" | grep -vx -e '' -e "$$" | sort -u)
  if [[ -n "$pids" ]]; then
    kill $pids 2>/dev/null || true
    sleep 0.5
    kill -9 $pids 2>/dev/null || true
  fi
  if [[ "${KEEP_TEST_BUILDS:-0}" != 1 ]]; then
    while IFS= read -r dir; do
      [[ -n "$dir" && -d "$dir" ]] || continue
      find "$dir" \( -name '*.app' -o -name DerivedData -o -name '*.xcarchive' \) -prune \
        -exec rm -rf {} + 2>/dev/null || true
    done <<< "$dirs"
  fi
  rm -f "$_hygiene_list"
  exit "$status"
}
builtin trap _hygiene_cleanup EXIT
