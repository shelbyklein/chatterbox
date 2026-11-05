# Sourced near the top of every scripts/test-*.sh (bash). Whatever a test run leaves behind
# goes away when it exits, pass or fail, so test runs don't pile up processes and app copies:
#
#  - processes the run started are stopped: its children, and anything still running from
#    its temp folders (fake providers and services outlive the scripts that start them);
#  - app bundles and Xcode build folders inside its temp folders are deleted, since each is a
#    full copy of Chatterbox that macOS then offers as an app. Logs and screenshots stay, so
#    renders can still be looked at; scripts/tidy.sh removes old temp folders later.
#  - simulators the run booted are shut down (see test_simulator), on every way out: a normal
#    exit, a failure, Ctrl-C, SIGTERM, or the parent shell going away (SIGHUP). A run killed
#    outright (SIGKILL) can't clean up; its simulator is on record in
#    ~/Library/Caches/Chatterbox/simulators/<udid> (pid, script, artifact folder), and
#    scripts/tidy.sh shuts down the ones whose run is gone.
#  - builds wait for the shared build slot (scripts/lib/build-lock.sh): `xcodebuild`, `swiftc`
#    and `swift build` in the test take it for as long as they run. `xcodebuild
#    test-without-building` doesn't: it runs on a device test_simulator booted under a
#    simulator slot (scripts/lib/sim-lock.sh, two at once), which goes back on exit.
#  - start_test_server starts a run's fixture server on a free port of its own, so two runs of
#    the same suite never collide on the test port.
#
# The script's own `trap '…' EXIT` keeps working: this file runs it first, then cleans up.
# KEEP_TEST_BUILDS=1 keeps the app bundles too, for debugging a failed run.

# macOS runs these with bash 3.2: no BASHPID, and empty arrays trip `set -u`, hence the
# `${a[@]+…}` forms. Temp folders are recorded in a file, because `d=$(mktemp -d …)` runs
# mktemp in a subshell that can't add to an array here.
_hygiene_exit_cmds=()
_hygiene_list=$(command mktemp /tmp/test-hygiene.XXXXXX)
_hygiene_simulators=''   # UDIDs this run booted, space-separated
_hygiene_sim_registry=${CHATTERBOX_SIMULATOR_REGISTRY:-$HOME/Library/Caches/Chatterbox/simulators}
_hygiene_script=${BASH_SOURCE[1]:-$0}

# The build lock's own EXIT trap would be replaced by ours below; cleanup releases the slot.
_build_lock_no_trap=1
source "$(dirname "${BASH_SOURCE[0]}")/build-lock.sh"
source "$(dirname "${BASH_SOURCE[0]}")/sim-lock.sh"

# Collect EXIT traps instead of letting each replace the last (or this file's). A script's own
# INT/TERM/HUP trap runs before the cleanup those signals trigger here.
trap() {
  local cmd=${1-} sig others=() exit_too=0
  [[ $# -ge 2 ]] || { builtin trap "$@"; return; }
  for sig in "${@:2}"; do
    case "$sig" in
      EXIT|0) exit_too=1 ;;
      INT|SIGINT|TERM|SIGTERM|HUP|SIGHUP)
        if [[ "$cmd" == - || -z "$cmd" ]]; then _hygiene_signal_trap "${sig#SIG}"
        else builtin trap "$cmd; _hygiene_on_signal ${sig#SIG}" "${sig#SIG}"; fi ;;
      *) others+=("$sig") ;;
    esac
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

# MARK: Simulators

# test_simulator iphone|ipad|duo [DEVICE_TYPE [RUNTIME]]
#   Prints the UDID of a test simulator of that kind and runtime, booted:
#   "Chatterbox test iPhone 26.2" (iPhone 17 Pro), "Chatterbox test iPad …" (iPad mini A17 Pro)
#   or "Chatterbox test iPhone Duo …", on the newest iOS runtime for the device unless one is
#   named. Tests reuse it run after run instead of making a device each; a device of another
#   type under the name is replaced. Booting takes a simulator slot (sim-lock.sh) for the rest of
#   the run, and the slot picks the device: slot 1 the name above, slot 2 "… 26.2 #2". So two
#   runs at once each have a device of their own, and never share one; a device left booted by a
#   run that died is taken over and shut down with this one. Build the tests first
#   (xcodebuild build-for-testing), then call this, so a run doesn't hold a device while it
#   waits for the build slot.
test_simulator() {
  local kind=$1 device_type=${2:-} runtime=${3:-} name udid state
  case "$kind" in
    iphone) name='Chatterbox test iPhone'; : "${device_type:=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}" ;;
    ipad) name='Chatterbox test iPad'; : "${device_type:=com.apple.CoreSimulator.SimDeviceType.iPad-mini-A17-Pro}" ;;
    duo) name='Chatterbox test iPhone Duo'; : "${device_type:=com.apple.CoreSimulator.SimDeviceType.iPhone-Duo}" ;;
    *) echo "test_simulator: iphone, ipad or duo, not '$kind'" >&2; return 2 ;;
  esac
  [[ -n "$runtime" ]] || runtime=$(_hygiene_newest_ios_runtime "$device_type") || return 1
  name="$name ${runtime##*iOS-}"; name=${name//-/.}
  sim_lock
  [[ "$_sim_lock_number" == 1 ]] || name="$name #$_sim_lock_number"
  # The existing device under this name, if it's the same device type on the same runtime.
  udid=$(xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
name, device_type, runtime = sys.argv[1:4]
devices = json.load(sys.stdin)["devices"]
for rt, found in devices.items():
    for d in found:
        if d.get("name") != name: continue
        if rt == runtime and d.get("deviceTypeIdentifier") == device_type and d.get("isAvailable", True): print(d["udid"], d["state"])
        else: print("replace", d["udid"])
' "$name" "$device_type" "$runtime" 2>/dev/null)
  local line
  while IFS= read -r line; do
    case "$line" in
      "replace "*) xcrun simctl shutdown "${line#replace }" >/dev/null 2>&1 || true; xcrun simctl delete "${line#replace }" >/dev/null 2>&1 || true ;;
    esac
  done <<< "$udid"
  udid=$(grep -v '^replace ' <<< "$udid" | head -1)
  state=${udid#* }; udid=${udid%% *}
  if [[ -z "$udid" ]]; then
    udid=$(xcrun simctl create "$name" "$device_type" "$runtime") || return 1
    state=Shutdown
  fi
  _hygiene_simulators="$_hygiene_simulators $udid"
  _hygiene_register_simulator "$udid"
  if [[ "$state" != Booted ]]; then xcrun simctl boot "$udid" >/dev/null || return 1; fi
  xcrun simctl bootstatus "$udid" -b >/dev/null || return 1
  printf '%s\n' "$udid"
}

# The newest installed iOS runtime that runs the device type (MOBILE_TEST_RUNTIME names one
# instead, for a reproducible regression).
_hygiene_newest_ios_runtime() {
  if [[ -n "${MOBILE_TEST_RUNTIME:-}" ]]; then printf '%s\n' "$MOBILE_TEST_RUNTIME"; return; fi
  xcrun simctl list runtimes -j | /usr/bin/python3 -c '
import json, sys
device_type = sys.argv[1]
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable", True)
            and any(t["identifier"] == device_type for t in r.get("supportedDeviceTypes", []))]
if not runtimes: sys.exit("no installed iOS simulator runtime runs " + device_type)
runtimes.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(runtimes[-1]["identifier"])' "$1"
}

# On record for scripts/tidy.sh: who booted the device, and where the run's artifacts went.
_hygiene_register_simulator() {
  command mkdir -p "$_hygiene_sim_registry"
  {
    printf 'pid %s\n' "$$"
    printf 'script %s\n' "$_hygiene_script"
    printf 'artifacts %s\n' "$(head -1 "$_hygiene_list" 2>/dev/null)"
    printf 'booted %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  } > "$_hygiene_sim_registry/$1"
  # The run's own artifact folder carries the id too, so a run's leftovers can be matched.
  local dir; dir=$(head -1 "$_hygiene_list" 2>/dev/null)
  [[ -n "$dir" && -d "$dir" ]] && printf '%s\n' "$1" >> "$dir/simulators"
  true
}

# Every device this run booted: test_simulator usually runs in a subshell (`$(…)`), so the
# registry, whose entries carry this script's pid, is the record that reaches cleanup.
_hygiene_shutdown_simulators() {
  local udid entry
  for entry in "$_hygiene_sim_registry"/*; do
    [[ -f "$entry" ]] && grep -qx "pid $$" "$entry" && _hygiene_simulators="$_hygiene_simulators $(basename "$entry")"
  done
  for udid in $_hygiene_simulators; do
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    command rm -f "$_hygiene_sim_registry/$udid"
  done
  _hygiene_simulators=''
}

# MARK: Test ports

# start_test_server LOG CMD…
#   Starts a run's fixture server (tests/mobile-*/server.py) in the background on a free port of
#   its own: the server binds port 0 and writes the port it got to $CHATTERBOX_TEST_PORT_FILE.
#   Sets test_server_pid and test_port, and exports CHATTERBOX_TEST_PORT and
#   TEST_RUNNER_CHATTERBOX_TEST_PORT (xcodebuild hands TEST_RUNNER_* to the XCUITest runner,
#   which passes the port on to the app it launches). Call it directly, not in `$(…)`. The
#   server is a child of the run, so cleanup stops it.
start_test_server() {
  local log=$1 file="$1.port" waited=0; shift
  command rm -f "$file"
  CHATTERBOX_TEST_PORT=0 CHATTERBOX_TEST_PORT_FILE="$file" "$@" > "$log" 2>&1 &
  test_server_pid=$!
  while [[ ! -s "$file" ]]; do
    if ! kill -0 "$test_server_pid" 2>/dev/null; then
      echo "start_test_server: the fixture server ended before it was listening (log: $log)" >&2
      command cat "$log" >&2 2>/dev/null; return 1
    fi
    (( waited >= 300 )) && { echo "start_test_server: no port from the fixture server after 30 s (log: $log)" >&2; return 1; }
    sleep 0.1; waited=$(( waited + 1 ))
  done
  test_port=$(command cat "$file")
  export CHATTERBOX_TEST_PORT=$test_port TEST_RUNNER_CHATTERBOX_TEST_PORT=$test_port
  echo "fixture server on 127.0.0.1:$test_port (pid $test_server_pid)" >&2
}

# free_port: a port nothing listens on now, for a test that has to name its port before
# starting the server that binds it (CHATTERBOX_COMPANION_PORT for an engine under test).
free_port() {
  /usr/bin/python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# MARK: Cleanup

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
  _hygiene_shutdown_simulators
  sim_unlock
  build_unlock
  if [[ "${KEEP_TEST_BUILDS:-0}" != 1 ]]; then
    while IFS= read -r dir; do
      [[ -n "$dir" && -d "$dir" ]] || continue
      find "$dir" \( -name '*.app' -o -name DerivedData -o -name '*.xcarchive' -o -name '*.xctestproducts' \) -prune \
        -exec rm -rf {} + 2>/dev/null || true
    done <<< "$dirs"
  fi
  rm -f "$_hygiene_list"
  exit "$status"
}
builtin trap _hygiene_cleanup EXIT

# A signal ends the run through the same cleanup, with the shell's usual status for it. Bash
# runs the trap once the current foreground command ends, so builds run in the background and
# are waited for (with_build_lock), and the handler stops them: SIGTERM, since a background
# child of a script ignores SIGINT.
_hygiene_on_signal() {
  local sig=$1 code=143
  case "$sig" in INT) code=130 ;; TERM) code=143 ;; HUP) code=129 ;; esac
  builtin trap - "$sig"
  pkill -TERM -P $$ 2>/dev/null || true
  exit "$code"
}
_hygiene_signal_trap() { builtin trap "_hygiene_on_signal $1" "$1"; }
_hygiene_signal_trap INT; _hygiene_signal_trap TERM; _hygiene_signal_trap HUP

# When the run is killed outright (SIGKILL, or the shell torn down with it), no trap runs: this
# watcher, on its own, shuts down the simulators on record for the run and gives its build and
# simulator slots back once the run's pid is gone. A normal cleanup stops it with the run's other children.
( while kill -0 $$ 2>/dev/null; do sleep 2; done
  for entry in "$_hygiene_sim_registry"/*; do
    [[ -f "$entry" ]] && grep -qx "pid $$" "$entry" || continue
    xcrun simctl shutdown "$(basename "$entry")" >/dev/null 2>&1 || true
    command rm -f "$entry"
  done
  while IFS= read -r slot; do
    [[ "$(command cat "$slot/pid" 2>/dev/null)" == "$$" ]] && command rm -rf "$slot"
  done < <(command find "$_build_lock_dir" "$_sim_lock_dir" -maxdepth 1 -name 'slot-*' 2>/dev/null)
) >/dev/null 2>&1 &
disown $! 2>/dev/null || true   # out of the job table: no "Killed" notice when cleanup stops it
