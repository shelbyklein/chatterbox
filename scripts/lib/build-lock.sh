# One build at a time across every checkout and worktree of Chatterbox (AGENTS.md, "Build and
# test hygiene"). Several agents build at once otherwise, and three Xcode builds plus simulator
# test suites side by side took the Mac to a load average of 120 on 16 cores.
#
# Sourced by the build scripts and, through test-hygiene.sh, by every scripts/test-*.sh. Once
# sourced, `xcodebuild`, `swiftc` and `swift build` in that script wait for a free build slot
# before running (a visible "waiting for another build (pid N, worktree X)" line), and
# xcodebuild gets `-jobs` capped to half the cores so a build leaves the machine usable.
#
#   build_lock          take a slot (held until the script exits); prints the waiting line
#   build_unlock        give it back early
#   with_build_lock CMD… run CMD under the lock
#
#   CHATTERBOX_BUILD_SLOTS=2     allow two builds at once (default 1)
#   CHATTERBOX_BUILD_JOBS=N      xcodebuild -jobs (default: half the cores, at least 2)
#   CHATTERBOX_BUILD_LOCK_DIR=…  where the slots live (default ~/Library/Caches/Chatterbox/build-lock)
#
# macOS has no flock(1), so a slot is a directory made with mkdir (atomic), holding the owner's
# pid and worktree. A slot whose owner is gone is taken over: a build killed with SIGKILL leaves
# its slot behind, and the next build reclaims it. bash 3.2 and zsh both run this.

_build_lock_dir=${CHATTERBOX_BUILD_LOCK_DIR:-$HOME/Library/Caches/Chatterbox/build-lock}
_build_lock_slots=${CHATTERBOX_BUILD_SLOTS:-1}
_build_lock_held=''      # the slot this process holds, if any
# The checkout this script builds in (named in the waiting line), from where this file lives.
if [[ -n "${BASH_SOURCE:-}" ]]; then _build_lock_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
else eval '_build_lock_root=$(cd "$(dirname "${(%):-%x}")/../.." && pwd)'; fi

_build_lock_pid() { command cat "$1/pid" 2>/dev/null; }
_build_lock_worktree() { command cat "$1/worktree" 2>/dev/null; }

# Whether a slot's owner still runs (an empty slot, mid-creation for under 5 s, counts as live).
_build_lock_live() {
  local pid; pid=$(_build_lock_pid "$1")
  if [[ -z "$pid" ]]; then
    local age; age=$(( $(date +%s) - $(stat -f %m "$1" 2>/dev/null || echo 0) ))
    (( age < 5 )); return
  fi
  kill -0 "$pid" 2>/dev/null
}

_build_lock_try() {  # try every slot once; sets _build_lock_held on success
  local n slot
  for (( n = 1; n <= _build_lock_slots; n++ )); do
    slot="$_build_lock_dir/slot-$n"
    # Taken in a subshell of this script ($(…) runs test_simulator, say): it's ours.
    if [[ "$(_build_lock_pid "$slot")" == "$$" ]]; then _build_lock_held=$slot; return 0; fi
    if command mkdir "$slot" 2>/dev/null; then
      printf '%s\n' "$$" > "$slot/pid"; printf '%s\n' "$_build_lock_root" > "$slot/worktree"
      _build_lock_held=$slot; return 0
    fi
    if ! _build_lock_live "$slot"; then
      # Its owner is gone: take it over, but only one taker wins (rename is atomic).
      local stale="$_build_lock_dir/stale-$n-$$"
      if command mv "$slot" "$stale" 2>/dev/null; then
        command rm -rf "$stale"
        if command mkdir "$slot" 2>/dev/null; then
          printf '%s\n' "$$" > "$slot/pid"; printf '%s\n' "$_build_lock_root" > "$slot/worktree"
          _build_lock_held=$slot; return 0
        fi
      fi
    fi
  done
  return 1
}

build_lock() {
  [[ -n "$_build_lock_held" ]] && return 0
  # A parent script already holds a slot for this run (it set the variable before starting us).
  if [[ -n "${CHATTERBOX_BUILD_LOCK_HELD:-}" ]] && kill -0 "$CHATTERBOX_BUILD_LOCK_HELD" 2>/dev/null; then return 0; fi
  command mkdir -p "$_build_lock_dir"
  local waited=0 said=0
  while ! _build_lock_try; do
    if (( ! said )) || (( waited % 60 == 0 )); then
      local n slot owners=''
      for (( n = 1; n <= _build_lock_slots; n++ )); do
        slot="$_build_lock_dir/slot-$n"
        [[ -d "$slot" ]] && owners="$owners${owners:+; }pid $(_build_lock_pid "$slot"), worktree $(_build_lock_worktree "$slot")"
      done
      echo "waiting for another build ($owners)" >&2
      said=1
    fi
    sleep 2; waited=$(( waited + 2 ))
  done
  (( said )) && echo "build slot free after ${waited}s" >&2
  export CHATTERBOX_BUILD_LOCK_HELD=$$
  return 0
}

build_unlock() {
  local slot
  # Every slot this script holds, including one a subshell of it took (find, not a glob: zsh
  # stops on a glob with no match).
  while IFS= read -r slot; do
    [[ -n "$slot" && -d "$slot" ]] || continue
    [[ "$(_build_lock_pid "$slot")" == "$$" ]] && command rm -rf "$slot"
  done < <(command find "$_build_lock_dir" -maxdepth 1 -name 'slot-*' 2>/dev/null)
  _build_lock_held=''
  unset CHATTERBOX_BUILD_LOCK_HELD
  return 0
}

with_build_lock() {
  local had=$_build_lock_held rc=0
  build_lock
  if type _hygiene_on_signal >/dev/null 2>&1; then
    # Under test-hygiene.sh: in the background and waited for, so a signal to the test runs its
    # cleanup at once (bash runs a trap only once a foreground command ends; a build can take
    # ten minutes). The handler stops this child first.
    "$@" & wait $! || rc=$?
  else
    "$@" || rc=$?
  fi
  [[ -z "$had" ]] && build_unlock
  return $rc
}

# xcodebuild -jobs: half the cores (two at least), unless the caller chose.
_build_lock_jobs() {
  if [[ -n "${CHATTERBOX_BUILD_JOBS:-}" ]]; then printf '%s' "$CHATTERBOX_BUILD_JOBS"; return; fi
  local cores; cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)
  local half=$(( cores / 2 )); (( half < 2 )) && half=2
  printf '%s' "$half"
}

xcodebuild() {
  local arg jobs=1 explicit=0
  for arg in "$@"; do
    case "$arg" in
      -jobs) explicit=1 ;;
      -exportArchive|-version|-list|-showBuildSettings|-showsdks|-showdestinations|-resolvePackageDependencies|-help|-usage|-checkFirstLaunchStatus|-runFirstLaunch) jobs=0 ;;
    esac
  done
  if (( jobs && ! explicit )); then
    with_build_lock command xcodebuild -jobs "$(_build_lock_jobs)" "$@"
  else
    with_build_lock command xcodebuild "$@"
  fi
}

swiftc() { with_build_lock command swiftc "$@"; }

swift() {
  case "${1:-}" in
    build|test|run) with_build_lock command swift "$@" ;;
    *) command swift "$@" ;;
  esac
}

# The slot goes back when the script ends, whatever way. Scripts that source test-hygiene.sh get
# this through its cleanup; others through this trap (a script's own `trap … EXIT` would replace
# it, so build scripts that set one call build_unlock there too).
if [[ -z "${_build_lock_no_trap:-}" ]]; then
  trap 'build_unlock' EXIT
fi
