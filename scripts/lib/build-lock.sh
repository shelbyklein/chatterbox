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
#   CHATTERBOX_BUILD_SLOTS=2     allow two builds at once (default 1; one while the Mac is busy)
#   CHATTERBOX_BUILD_JOBS=N      xcodebuild -jobs (default: half the cores, a quarter while the
#                                Mac is busy; at least 2)
#   CHATTERBOX_BUILD_LOCK_DIR=…  where the slots live (default ~/Library/Caches/Chatterbox/build-lock)
#
# The Mac's pressure (the background service writes ~/Library/Caches/Chatterbox/pressure.json
# every 10 s; ChatterboxDaemon/PressureMonitor.swift): while it's busy, one build at a time
# whatever CHATTERBOX_BUILD_SLOTS says; while it's overloaded, new builds wait until it's less
# loaded (running ones carry on; nothing is ever stopped). The waiting line says so. A file older
# than a minute (the service isn't running) is ignored.
#   CHATTERBOX_PRESSURE_FILE=…           read this instead (tests)
#   CHATTERBOX_BUILD_IGNORE_PRESSURE=1   build whatever the pressure
#
# macOS has no flock(1), so a slot is a directory made with mkdir (atomic), holding the owner's
# pid and worktree. A slot whose owner is gone is taken over: a build killed with SIGKILL leaves
# its slot behind, and the next build reclaims it. bash 3.2 and zsh both run this.

_build_lock_dir=${CHATTERBOX_BUILD_LOCK_DIR:-$HOME/Library/Caches/Chatterbox/build-lock}
_build_lock_slots=${CHATTERBOX_BUILD_SLOTS:-1}
_build_lock_held=''      # the slot this process holds, if any
_build_lock_level=ok     # the Mac's pressure, as last read: ok, busy or overloaded
_build_lock_pressure_why=''
# The checkout this script builds in (named in the waiting line), from where this file lives.
if [[ -n "${BASH_SOURCE:-}" ]]; then _build_lock_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
else eval '_build_lock_root=$(cd "$(dirname "${(%):-%x}")/../.." && pwd)'; fi

# Never failing: a slot can go between being listed and being read, and a failed read in an
# assignment would end a `set -e` script while it waits.
_build_lock_pid() { command cat "$1/pid" 2>/dev/null || true; }
_build_lock_worktree() { command cat "$1/worktree" 2>/dev/null || true; }

# Whether a slot's owner still runs (an empty slot, mid-creation for under 5 s, counts as live).
_build_lock_live() {
  local pid; pid=$(_build_lock_pid "$1")
  if [[ -z "$pid" ]]; then
    local age; age=$(( $(date +%s) - $(stat -f %m "$1" 2>/dev/null || echo 0) ))
    (( age < 5 )); return
  fi
  kill -0 "$pid" 2>/dev/null
}

# Reads the Mac's pressure into _build_lock_level and _build_lock_pressure_why (its reasons).
_build_lock_pressure() {
  _build_lock_level=ok; _build_lock_pressure_why=''
  [[ -n "${CHATTERBOX_BUILD_IGNORE_PRESSURE:-}" ]] && return 0
  local file=${CHATTERBOX_PRESSURE_FILE:-$HOME/Library/Caches/Chatterbox/pressure.json} level updated now
  [[ -f "$file" ]] || return 0
  level=$(command plutil -extract level raw -o - "$file" 2>/dev/null) || return 0
  updated=$(command plutil -extract updated raw -o - "$file" 2>/dev/null) || return 0
  [[ "$updated" =~ ^[0-9]+$ ]] || return 0
  now=$(date +%s)
  (( now - updated <= 60 && updated - now <= 60 )) || return 0
  case "$level" in
    busy|overloaded)
      _build_lock_level=$level
      _build_lock_pressure_why=$(command plutil -extract summary raw -o - "$file" 2>/dev/null) ;;
  esac
  return 0
}

# Whether a live slot other than this script's is held (any slot, whatever the slot count).
_build_lock_others_live() {
  local slot
  while IFS= read -r slot; do
    [[ -n "$slot" && -d "$slot" ]] || continue
    [[ "$(_build_lock_pid "$slot")" == "$$" ]] && continue
    _build_lock_live "$slot" && return 0
  done < <(command find "$_build_lock_dir" -maxdepth 1 -name 'slot-*' 2>/dev/null)
  return 1
}

_build_lock_try() {  # try every slot once; sets _build_lock_held on success
  local n slot slots=$_build_lock_slots
  # Busy: one build at a time, however many slots are allowed (and none beside one already
  # running in another slot).
  if [[ "$_build_lock_level" != ok ]]; then
    slots=1
    if _build_lock_others_live; then
      [[ "$(_build_lock_pid "$_build_lock_dir/slot-1")" == "$$" ]] && { _build_lock_held="$_build_lock_dir/slot-1"; return 0; }
      return 1
    fi
  fi
  for (( n = 1; n <= slots; n++ )); do
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
  local waited=0 said='' line slot owners
  while :; do
    _build_lock_pressure
    if [[ "$_build_lock_level" == overloaded ]]; then
      # Overloaded: no new build, slot or not, until it's less loaded.
      line="waiting: the Mac is overloaded (${_build_lock_pressure_why:-see Chatterbox}); new builds wait until it's less loaded (CHATTERBOX_BUILD_IGNORE_PRESSURE=1 builds anyway)"
    elif _build_lock_try; then
      break
    else
      owners=''
      while IFS= read -r slot; do
        [[ -n "$slot" && -d "$slot" ]] || continue
        owners="$owners${owners:+; }pid $(_build_lock_pid "$slot"), worktree $(_build_lock_worktree "$slot")"
      done < <(command find "$_build_lock_dir" -maxdepth 1 -name 'slot-*' 2>/dev/null | sort)
      line="waiting for another build ($owners)"
      [[ "$_build_lock_level" == busy ]] && line="$line; the Mac is busy (${_build_lock_pressure_why:-see Chatterbox}), so builds go one at a time"
    fi
    if [[ "$line" != "$said" ]] || (( waited % 60 == 0 )); then echo "$line" >&2; said=$line; fi
    sleep 2; waited=$(( waited + 2 ))
  done
  [[ -n "$said" ]] && echo "build slot free after ${waited}s" >&2
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

# xcodebuild -jobs: half the cores (two at least), a quarter while the Mac is under pressure,
# unless the caller chose.
_build_lock_jobs() {
  if [[ -n "${CHATTERBOX_BUILD_JOBS:-}" ]]; then printf '%s' "$CHATTERBOX_BUILD_JOBS"; return; fi
  local cores; cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)
  local half=$(( cores / 2 )); (( half < 2 )) && half=2
  _build_lock_pressure
  if [[ "$_build_lock_level" != ok ]]; then half=$(( cores / 4 )); (( half < 2 )) && half=2; fi
  printf '%s' "$half"
}

# Xcode's compilation cache, shared by every checkout and worktree: a compile whose inputs some
# other build already compiled (the same sources, flags and SDK) is replayed instead of run.
# Paths are mapped (the checkout's root to /^wt, Xcode's own maps for the project, derived and
# product folders), so a new worktree's first build reuses what the main checkout or another
# worktree built. Measured 2026-11-05 (16 cores, other builds running): a new worktree's first
# Mac Debug build 49 s cold, 11 s warm-started with the cache; iOS Release 85 s, 7 s.
#   CHATTERBOX_COMPILE_CACHE=0   build without it
#   CHATTERBOX_COMPILE_CACHE_DIR=…  where it lives (default ~/Library/Caches/Chatterbox/CompilationCache)
# Debug info then names sources as /^wt/…; a build that sets COMPILATION_CACHE_ENABLE_CACHING
# itself is left as it asks.
_build_lock_cache_args() {
  [[ "${CHATTERBOX_COMPILE_CACHE:-1}" == 0 ]] && return 0
  local arg
  for arg in "$@"; do [[ "$arg" == COMPILATION_CACHE_ENABLE_CACHING=* ]] && return 0; done
  printf '%s\n' COMPILATION_CACHE_ENABLE_CACHING=YES \
    "COMPILATION_CACHE_CAS_PATH=${CHATTERBOX_COMPILE_CACHE_DIR:-$HOME/Library/Caches/Chatterbox/CompilationCache}" \
    SWIFT_ENABLE_PREFIX_MAPPING=YES SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES \
    CLANG_ENABLE_PREFIX_MAPPING=YES CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES \
    "SWIFT_OTHER_PREFIX_MAPPINGS=$_build_lock_root=/^wt" "CLANG_OTHER_PREFIX_MAPPINGS=$_build_lock_root=/^wt"
}

xcodebuild() {
  local arg jobs=1 explicit=0 cache=() line
  for arg in "$@"; do
    case "$arg" in
      -jobs) explicit=1 ;;
      -exportArchive|-version|-list|-showBuildSettings|-showsdks|-showdestinations|-resolvePackageDependencies|-help|-usage|-checkFirstLaunchStatus|-runFirstLaunch) jobs=0 ;;
    esac
  done
  if (( jobs )); then
    while IFS= read -r line; do [[ -n "$line" ]] && cache+=("$line"); done < <(_build_lock_cache_args "$@")
  fi
  if (( jobs && ! explicit )); then
    with_build_lock command xcodebuild -jobs "$(_build_lock_jobs)" "$@" ${cache[@]+"${cache[@]}"}
  else
    with_build_lock command xcodebuild "$@" ${cache[@]+"${cache[@]}"}
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
