# A few builds at a time across every checkout and worktree of Chatterbox (AGENTS.md, "Build
# and test hygiene"), as many as the Mac's pressure allows. Several agents build at once
# otherwise, and unbounded Xcode builds plus simulator test suites side by side took the Mac to a
# load average of 120 on 16 cores.
#
# Sourced by the build scripts and, through test-hygiene.sh, by every scripts/test-*.sh. Once
# sourced, `xcodebuild`, `swiftc` and `swift build` in that script wait for a free build slot
# before running (a visible "waiting for another build (pid N, worktree X)" line), and
# xcodebuild gets `-jobs` set so the builds running share the cores: max(4, cores / builds
# running), counting itself (16 cores: 16 alone, 8 beside one other, 5 beside two; 4 while busy).
# `xcodebuild test-without-building` builds nothing and doesn't wait: simulator test runs build
# with build-for-testing (under the slot), then run on a device booted under a simulator slot
# (sim-lock.sh), so the build slot is free while XCUITests drive the app.
#
#   build_lock          take a slot (held until the script exits); prints the waiting line
#   build_unlock        give it back early
#   with_build_lock CMD… run CMD under the lock
#
#   CHATTERBOX_BUILD_SLOTS=N     allow N builds at once, whatever the pressure (but none new
#                                while the Mac is overloaded)
#   CHATTERBOX_BUILD_JOBS=N      xcodebuild -jobs (default: shared, as above)
#   CHATTERBOX_BUILD_LOCK_DIR=…  where the slots live (default ~/Library/Caches/Chatterbox/build-lock)
#
# The Mac's pressure (the background service writes ~/Library/Caches/Chatterbox/pressure.json
# every 10 s; ChatterboxDaemon/PressureMonitor.swift) sets how many builds may run: 3 while it's
# OK, 1 while it's busy, and while it's overloaded none new (running ones carry on; nothing is
# ever stopped). The waiting line says why. With no file, or one older than a minute (the service
# isn't running), 2.
#   CHATTERBOX_PRESSURE_FILE=…           read this instead (tests)
#   CHATTERBOX_BUILD_IGNORE_PRESSURE=1   build whatever the pressure
#
# macOS has no flock(1), so a slot is a directory made with mkdir (atomic), holding the owner's
# pid and worktree. A slot whose owner is gone is taken over: a build killed with SIGKILL leaves
# its slot behind, and the next build reclaims it. bash 3.2 and zsh both run this.

_build_lock_dir=${CHATTERBOX_BUILD_LOCK_DIR:-$HOME/Library/Caches/Chatterbox/build-lock}
_build_lock_held=''      # the slot this process holds, if any
_build_lock_level=ok     # the Mac's pressure, as last read: ok, busy or overloaded
_build_lock_fresh=0      # whether that came from a current pressure.json (1) or is a guess (0)
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
  _build_lock_level=ok; _build_lock_pressure_why=''; _build_lock_fresh=0
  [[ -n "${CHATTERBOX_BUILD_IGNORE_PRESSURE:-}" ]] && return 0
  local file=${CHATTERBOX_PRESSURE_FILE:-$HOME/Library/Caches/Chatterbox/pressure.json} level updated now
  [[ -f "$file" ]] || return 0
  level=$(command plutil -extract level raw -o - "$file" 2>/dev/null) || return 0
  updated=$(command plutil -extract updated raw -o - "$file" 2>/dev/null) || return 0
  [[ "$updated" =~ ^[0-9]+$ ]] || return 0
  now=$(date +%s)
  (( now - updated <= 60 && updated - now <= 60 )) || return 0
  _build_lock_fresh=1
  case "$level" in
    busy|overloaded)
      _build_lock_level=$level
      _build_lock_pressure_why=$(command plutil -extract summary raw -o - "$file" 2>/dev/null) ;;
  esac
  return 0
}

# How many builds may run now: CHATTERBOX_BUILD_SLOTS, else by the pressure (3 OK, 1 busy; 2
# without a current reading). Overloaded is handled by build_lock (none new).
_build_lock_slot_count() {
  if [[ -n "${CHATTERBOX_BUILD_SLOTS:-}" ]]; then printf '%s' "$CHATTERBOX_BUILD_SLOTS"; return; fi
  if [[ "$_build_lock_level" == busy ]]; then printf 1
  elif (( _build_lock_fresh )); then printf 3
  else printf 2; fi
}

# How many live slots are held (any slot, whatever the slot count), counting this script's own
# only when `mine` is passed.
_build_lock_count() {
  local slot count=0
  while IFS= read -r slot; do
    [[ -n "$slot" && -d "$slot" ]] || continue
    if [[ "$(_build_lock_pid "$slot")" == "$$" ]]; then [[ "${1:-}" == mine ]] && count=$(( count + 1 )); continue; fi
    _build_lock_live "$slot" && count=$(( count + 1 ))
  done < <(command find "$_build_lock_dir" -maxdepth 1 -name 'slot-*' 2>/dev/null)
  printf '%s' "$count"
}

_build_lock_try() {  # try every slot once; sets _build_lock_held on success
  local n slot slots
  slots=$(_build_lock_slot_count)
  # As many running as allowed already (slots taken when more were allowed count too): wait,
  # unless this script took one in a subshell.
  if (( $(_build_lock_count) >= slots )); then
    for (( n = 1; n <= 8; n++ )); do
      [[ "$(_build_lock_pid "$_build_lock_dir/slot-$n")" == "$$" ]] && { _build_lock_held="$_build_lock_dir/slot-$n"; return 0; }
    done
    return 1
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
      if [[ "$_build_lock_level" == busy ]]; then line="$line; the Mac is busy (${_build_lock_pressure_why:-see Chatterbox}), so builds go $(_build_lock_slot_count) at a time"
      else line="$line; $(_build_lock_slot_count) at a time"; fi
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
  _build_lock_run "$@" || rc=$?
  [[ -z "$had" ]] && build_unlock
  return $rc
}

_build_lock_run() {
  local rc=0
  if type _hygiene_on_signal >/dev/null 2>&1; then
    # Under test-hygiene.sh: in the background and waited for, so a signal to the test runs its
    # cleanup at once (bash runs a trap only once a foreground command ends; a build can take
    # ten minutes). The handler stops this child first.
    "$@" & wait $! || rc=$?
  else
    "$@" || rc=$?
  fi
  return $rc
}

# One build at a time into a given DerivedData folder: two runs from the same checkout (say two
# phone suites side by side) would otherwise both open its build database ("unable to attach
# DB"). A lock directory beside the folder, holding the owner's pid; a dead owner's is reclaimed.
_build_lock_dd_take() {
  local lock="$1.building" waited=0 owner
  command mkdir -p "$(dirname "$1")"
  until command mkdir "$lock" 2>/dev/null; do
    owner=$(command cat "$lock/pid" 2>/dev/null || true)
    if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then command rm -rf "$lock"; continue; fi
    (( waited % 60 == 0 )) && echo "waiting for another build into $(basename "$1") (pid ${owner:-?})" >&2
    sleep 2; waited=$(( waited + 2 ))
  done
  echo "${BASHPID:-$$}" > "$lock/pid"
}
_build_lock_dd_release() { [[ "$(command cat "$1.building/pid" 2>/dev/null)" == "${BASHPID:-$$}" ]] && command rm -rf "$1.building"; return 0; }

# Keep a build's products stable while a caller validates, publishes and installs them.
# The top-level EXIT cleanup releases it on failure; nested xcodebuild reuses this lock.
with_derived_data_lock() {
  local dd=$1; shift
  _build_lock_dd_take "$dd"
  _build_lock_dd_held=$dd
  "$@"
  _build_lock_dd_release "$dd"
  unset _build_lock_dd_held
}

# xcodebuild -jobs, once this build has its slot: the builds running share the cores,
# max(4, cores / builds running, this one included); a quarter of the cores (4 at least) while the
# Mac is under pressure; unless the caller chose.
_build_lock_jobs() {
  if [[ -n "${CHATTERBOX_BUILD_JOBS:-}" ]]; then printf '%s' "$CHATTERBOX_BUILD_JOBS"; return; fi
  local cores running jobs; cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)
  _build_lock_pressure
  running=$(_build_lock_count mine); (( running < 1 )) && running=1
  [[ "$_build_lock_level" != ok ]] && (( running < 4 )) && running=4
  jobs=$(( cores / running )); (( jobs < 4 )) && jobs=4
  printf '%s' "$jobs"
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
      # Runs tests already built: no build slot (the device's simulator slot is the limit).
      # Each test gets a time limit, so a hung app fails in about 3 minutes, not 10
      # (the slowest passing test takes under 2). CHATTERBOX_TEST_ALLOWANCE=N seconds changes it.
      test-without-building)
        local limits=()
        [[ " $* " == *" -test-timeouts-enabled "* ]] || limits=(-test-timeouts-enabled YES
          -default-test-execution-time-allowance "${CHATTERBOX_TEST_ALLOWANCE:-180}"
          -maximum-test-execution-time-allowance "$(( ${CHATTERBOX_TEST_ALLOWANCE:-180} * 2 ))")
        _build_lock_run command xcodebuild "$@" ${limits[@]+"${limits[@]}"}; return ;;
      -jobs) explicit=1 ;;
      -exportArchive|-version|-list|-showBuildSettings|-showsdks|-showdestinations|-resolvePackageDependencies|-help|-usage|-checkFirstLaunchStatus|-runFirstLaunch) jobs=0 ;;
    esac
  done
  if (( jobs )); then
    while IFS= read -r line; do [[ -n "$line" ]] && cache+=("$line"); done < <(_build_lock_cache_args "$@")
  fi
  local dd='' prev=''
  for arg in "$@"; do [[ "$prev" == -derivedDataPath ]] && dd=$arg; prev=$arg; done
  if (( jobs )) && [[ -n "$dd" && "${_build_lock_dd_held:-}" != "$dd" ]]; then
    local rc=0
    _build_lock_dd_take "$dd"
    _build_lock_xcodebuild "$(( jobs && ! explicit ))" "$@" ${cache[@]+"${cache[@]}"} || rc=$?
    _build_lock_dd_release "$dd"
    return $rc
  fi
  _build_lock_xcodebuild "$(( jobs && ! explicit ))" "$@" ${cache[@]+"${cache[@]}"}
}

# The build itself, under a slot; `addjobs` 1 sets -jobs to the share of the cores.
_build_lock_xcodebuild() {
  local addjobs=$1; shift
  if (( addjobs )); then
    # The slot first, so -jobs can count the builds running beside it.
    local had=$_build_lock_held rc=0 n
    build_lock
    n=$(_build_lock_jobs)
    with_build_lock command xcodebuild -jobs "$n" "$@" || rc=$?
    [[ -z "$had" ]] && build_unlock
    return $rc
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
  trap '[[ -z "${_build_lock_dd_held:-}" ]] || _build_lock_dd_release "$_build_lock_dd_held"; build_unlock' EXIT
fi
