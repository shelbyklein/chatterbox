#!/bin/bash
# test-hygiene.sh and simulators: a test run builds under the build slot and gives it back, then
# boots a test device under a simulator slot (scripts/lib/sim-lock.sh) and shuts it down on
# every way out (exit, Ctrl-C, SIGTERM, SIGHUP), giving the slot back. Two runs at once each get
# a device of their own; a third waits; while the Mac is busy they go one at a time. A run killed
# outright leaves its device on record, and scripts/tidy.sh --simulators shuts it down. Runs
# against a stub `xcrun` that keeps its devices in a file, so no simulator is touched.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
fixture=$(mktemp -d /tmp/chatterbox-test-hygiene-sims.XXXXXX)
export CHATTERBOX_BUILD_LOCK_DIR="$fixture/lock" CHATTERBOX_SIM_LOCK_DIR="$fixture/simlock"
export CHATTERBOX_SIMULATOR_REGISTRY="$fixture/registry" CHATTERBOX_PRESSURE_FILE="$fixture/pressure.json"
export STUB_LOG="$fixture/simctl.log" STUB_STATE="$fixture/devices.json"
unset CHATTERBOX_BUILD_LOCK_HELD CHATTERBOX_SIM_SLOTS CHATTERBOX_BUILD_IGNORE_PRESSURE
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }

mkdir -p "$fixture/bin"
# The stub simctl: devices (name, udid, state) in a JSON file; every call logged.
cat > "$fixture/bin/xcrun" <<'EOF'
#!/usr/bin/python3
import fcntl, json, os, sys, uuid
args = sys.argv[1:]
with open(os.environ["STUB_LOG"], "a") as log: log.write(" ".join(args) + "\n")
path = os.environ["STUB_STATE"]
lock = open(path + ".lock", "w"); fcntl.flock(lock, fcntl.LOCK_EX)
devices = json.load(open(path)) if os.path.exists(path) else []
def save(): json.dump(devices, open(path, "w"))
def find(udid): return next(d for d in devices if d["udid"] == udid)
rt = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
if args[:3] == ["simctl", "list", "devices"]:
    if "-j" in args:
        print(json.dumps({"devices": {rt: [dict(d, isAvailable=True, deviceTypeIdentifier=d["type"]) for d in devices]}}))
    else:
        print("== Devices ==\n-- iOS 26.2 --")
        for d in devices: print("    %s (%s) (%s) " % (d["name"], d["udid"], d["state"]))
elif args[:3] == ["simctl", "list", "runtimes"]:
    print(json.dumps({"runtimes": [{"platform": "iOS", "isAvailable": True, "version": "26.2", "identifier": rt,
        "supportedDeviceTypes": [{"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"}]}]}))
elif args[:2] == ["simctl", "create"]:
    udid = str(uuid.uuid4()).upper(); devices.append({"name": args[2], "udid": udid, "state": "Shutdown", "type": args[3]}); save(); print(udid)
elif args[:2] == ["simctl", "boot"]: find(args[2])["state"] = "Booted"; save()
elif args[:2] == ["simctl", "shutdown"]: find(args[2])["state"] = "Shutdown"; save()
elif args[:2] == ["simctl", "delete"]: devices[:] = [d for d in devices if d["udid"] != args[2]]; save()
EOF
chmod +x "$fixture/bin/xcrun"
# xcodebuild: build-for-testing is quick; running the tests takes a while, as XCUITests do.
cat > "$fixture/bin/xcodebuild" <<'EOF'
#!/bin/bash
# STUB_OVERLOAD_AFTER_BUILD: the Mac goes overloaded once the build is done (before booting).
for arg in "$@"; do
  if [[ "$arg" == build-for-testing ]]; then
    sleep 0.2
    [[ -n "${STUB_OVERLOAD_AFTER_BUILD:-}" ]] && printf '{"level":"overloaded","updated":%s,"summary":"load 300"}\n' "$(date +%s)" > "$CHATTERBOX_PRESSURE_FILE"
    exit 0
  fi
done
sleep 60
EOF
chmod +x "$fixture/bin/xcodebuild"
export PATH="$fixture/bin:$PATH"

# A test run, as the phone suites go: build, boot (writes the device to OUT/sim), run until
# stopped. `run.sh OUT exit` ends right after booting; `run.sh OUT hold` ends when OUT/release
# appears.
cat > "$fixture/run.sh" <<EOF
#!/bin/bash
source "$root/scripts/lib/test-hygiene.sh"
set -euo pipefail
out=\$1; mkdir -p "\$out"
artifacts=\$(mktemp -d "\$out/run.XXXXXX")
xcodebuild -scheme Regression build-for-testing
sim=\$(test_simulator iphone)
echo "\$artifacts" > "\$out/artifacts"
ls "$fixture/lock" > "\$out/build-slots" 2>/dev/null || true
echo "\$sim" > "\$out/sim"
case "\${2:-}" in
  exit) exit 0 ;;
  hold) while [[ ! -f "\$out/release" ]]; do sleep 0.1; done; exit 0 ;;
esac
xcodebuild -testProductsPath "\$artifacts/tests.xctestproducts" -destination "platform=iOS Simulator,id=\$sim" test-without-building
EOF
chmod +x "$fixture/run.sh"

# A background job of this script would have SIGINT ignored (and so untrappable); start runs
# the way a terminal does, with the default handlers.
launch() { exec /usr/bin/python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execv(sys.argv[1], sys.argv[1:])' "$@"; }
reset() { rm -rf "$STUB_LOG" "$STUB_STATE" "$fixture/registry" "$fixture/lock" "$fixture/simlock" "$fixture"/r? "$CHATTERBOX_PRESSURE_FILE"; }
state() { /usr/bin/python3 -c 'import json,sys; print(next((d["state"] for d in json.load(open(sys.argv[1])) if d["udid"]==sys.argv[2]), "gone"))' "$STUB_STATE" "$1"; }
name() { /usr/bin/python3 -c 'import json,sys; print(next(d["name"] for d in json.load(open(sys.argv[1])) if d["udid"]==sys.argv[2]))' "$STUB_STATE" "$1"; }
count() { /usr/bin/python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$STUB_STATE"; }
wait_booted() {  # wait_booted OUT
  for _ in $(seq 100); do [[ -f "$1/sim" ]] && break; sleep 0.1; done
  [[ -f "$1/sim" ]] || fail "the run never booted its device: $(cat "$STUB_LOG" 2>/dev/null)"
}
wait_gone() {  # wait_gone PID WAY
  for _ in $(seq 100); do kill -0 "$1" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$1" 2>/dev/null; then kill -9 "$1"; fail "$2: the run didn't end"; fi
}
check_clean() {  # check_clean WAY OUT…
  local way=$1 out; shift
  for out in "$@"; do
    [[ "$(state "$(cat "$out/sim")")" == Shutdown ]] || fail "$way: device $(cat "$out/sim") wasn't shut down"
    grep -q "$(cat "$out/sim")" "$(cat "$out/artifacts")/simulators" || fail "$way: the artifact folder doesn't name the device"
  done
  [[ -z "$(ls "$fixture/registry" 2>/dev/null)" ]] || fail "$way: registry entry left: $(ls "$fixture/registry")"
  [[ -z "$(ls "$fixture/lock" 2>/dev/null)" ]] || fail "$way: build slot left: $(ls "$fixture/lock")"
  [[ -z "$(ls "$fixture/simlock" 2>/dev/null)" ]] || fail "$way: simulator slot left: $(ls "$fixture/simlock")"
}

echo "== a run that exits normally"
reset; "$fixture/run.sh" "$fixture/r1" exit; check_clean exit "$fixture/r1"
[[ "$(name "$(cat "$fixture/r1/sim")")" == "Chatterbox test iPhone 26.2" ]] || fail "the device isn't the shared one: $(cat "$STUB_LOG")"
[[ -z "$(cat "$fixture/r1/build-slots")" ]] || fail "the build slot was still held while the device booted: $(cat "$fixture/r1/build-slots")"
pass "exit: device shut down, registry and slots clear, build slot free before booting, artifacts name the device"

echo "== the device is reused, not made again"
rm -rf "$fixture/r1"; : > "$STUB_LOG"
"$fixture/run.sh" "$fixture/r1" exit; check_clean reuse "$fixture/r1"
grep -q 'simctl create' "$STUB_LOG" && fail "a second device was created: $(cat "$STUB_LOG")"
grep -q "simctl boot $(cat "$fixture/r1/sim")" "$STUB_LOG" || fail "the existing device wasn't booted"
pass "reuse: the shut-down device was booted again, not created"

for sig in TERM INT HUP; do
  echo "== a run stopped with SIG$sig"
  reset
  launch "$fixture/run.sh" "$fixture/r1" > "$fixture/run.$sig.log" 2>&1 &
  pid=$!
  wait_booted "$fixture/r1"
  sim=$(cat "$fixture/r1/sim")
  [[ -f "$fixture/registry/$sim" ]] || fail "$sig: no registry entry while booted"
  grep -q "^pid $pid$" "$fixture/registry/$sim" || fail "$sig: registry entry doesn't carry the run's pid"
  [[ -d "$fixture/simlock/slot-1" ]] || fail "$sig: booting didn't take a simulator slot"
  for _ in $(seq 50); do pgrep -f "$fixture/bin/xcodebuild .*test-without-building" >/dev/null && break; sleep 0.1; done
  [[ -z "$(ls "$fixture/lock" 2>/dev/null)" ]] || fail "$sig: the tests ran under the build slot: $(ls "$fixture/lock")"
  kill -"$sig" "$pid"
  wait_gone "$pid" "$sig"
  check_clean "$sig" "$fixture/r1"
  pass "SIG$sig: device shut down, registry and slot clear (the tests ran with the build slot free)"
done

echo "== two runs at once: a device each; a third waits for a slot"
reset
launch "$fixture/run.sh" "$fixture/r1" hold > "$fixture/r1.log" 2>&1 &
p1=$!
wait_booted "$fixture/r1"
launch "$fixture/run.sh" "$fixture/r2" hold > "$fixture/r2.log" 2>&1 &
p2=$!
wait_booted "$fixture/r2"
s1=$(cat "$fixture/r1/sim") s2=$(cat "$fixture/r2/sim")
[[ "$s1" != "$s2" ]] || fail "two runs share device $s1"
[[ "$(name "$s1")" == "Chatterbox test iPhone 26.2" && "$(name "$s2")" == "Chatterbox test iPhone 26.2 #2" ]] || fail "names: $(name "$s1") / $(name "$s2")"
[[ "$(state "$s1") $(state "$s2")" == "Booted Booted" ]] || fail "both should be booted: $(state "$s1") $(state "$s2")"
launch "$fixture/run.sh" "$fixture/r3" hold > "$fixture/r3.log" 2>&1 &
p3=$!
for _ in $(seq 50); do grep -q "waiting for a simulator slot" "$fixture/r3.log" 2>/dev/null && break; sleep 0.1; done
grep -q "waiting for a simulator slot (pid $p1, worktree $root; pid $p2, worktree $root)" "$fixture/r3.log" || fail "the third run didn't wait for a slot: $(cat "$fixture/r3.log")"
[[ ! -f "$fixture/r3/sim" ]] || fail "the third run booted a device while two ran"
touch "$fixture/r1/release"; wait_gone "$p1" "first of two"
[[ "$(state "$s1")" == Shutdown && "$(state "$s2")" == Booted ]] || fail "ending one run touched the other's device: $(state "$s1") $(state "$s2")"
wait_booted "$fixture/r3"
[[ "$(cat "$fixture/r3/sim")" == "$s1" ]] || fail "the third run didn't take the freed slot's device: $(cat "$fixture/r3/sim")"
grep -q "simulator slot 1 free after" "$fixture/r3.log" || fail "the third run didn't say it got slot 1: $(cat "$fixture/r3.log")"
touch "$fixture/r2/release" "$fixture/r3/release"; wait_gone "$p2" second; wait_gone "$p3" third
check_clean "two at once" "$fixture/r1" "$fixture/r2" "$fixture/r3"
[[ "$(count)" == 2 ]] || fail "expected two devices, slot 1's and slot 2's: $(cat "$STUB_STATE")"
pass "two at once: separate devices (… 26.2, … 26.2 #2), the third waited and reused slot 1's, all shut down"

echo "== the Mac is busy: one simulator run at a time"
reset
printf '{"level":"busy","updated":%s,"summary":"load 40"}\n' "$(date +%s)" > "$CHATTERBOX_PRESSURE_FILE"
launch "$fixture/run.sh" "$fixture/r1" hold > "$fixture/r1.log" 2>&1 &
p1=$!
wait_booted "$fixture/r1"
launch "$fixture/run.sh" "$fixture/r2" hold > "$fixture/r2.log" 2>&1 &
p2=$!
for _ in $(seq 50); do grep -q "waiting for a simulator slot" "$fixture/r2.log" 2>/dev/null && break; sleep 0.1; done
grep -q "the Mac is busy, so simulator runs go one at a time" "$fixture/r2.log" || fail "busy: the second run didn't wait: $(cat "$fixture/r2.log")"
[[ ! -f "$fixture/r2/sim" ]] || fail "busy: a second device booted"
touch "$fixture/r1/release"; wait_gone "$p1" busy-first
wait_booted "$fixture/r2"
touch "$fixture/r2/release"; wait_gone "$p2" busy-second
check_clean busy "$fixture/r1" "$fixture/r2"
printf '{"level":"busy","updated":%s}\n' "$(( $(date +%s) - 600 ))" > "$CHATTERBOX_PRESSURE_FILE"
[[ "$(_sim_lock_level)" == ok ]] || fail "a stale pressure file still counted"
pass "busy: the second run waited for the first, said why; a stale pressure file is ignored"

echo "== the Mac is overloaded: no new simulator run until it's less loaded"
reset
# The build lock holds new builds while overloaded too; this goes overloaded after the build,
# so the wait is the simulator slot's own.
STUB_OVERLOAD_AFTER_BUILD=1 launch "$fixture/run.sh" "$fixture/r1" exit > "$fixture/r1.log" 2>&1 &
p1=$!
for _ in $(seq 80); do grep -q "new simulator runs wait" "$fixture/r1.log" 2>/dev/null && break; sleep 0.1; done
grep -q "waiting: the Mac is overloaded; new simulator runs wait until it's less loaded" "$fixture/r1.log" || fail "overloaded: the run didn't wait: $(cat "$fixture/r1.log")"
[[ ! -f "$fixture/r1/sim" ]] || fail "overloaded: a device booted"
printf '{"level":"ok","updated":%s}\n' "$(date +%s)" > "$CHATTERBOX_PRESSURE_FILE"
wait_booted "$fixture/r1"; wait_gone "$p1" overloaded
check_clean overloaded "$fixture/r1"
pass "overloaded: the run waited, said why, and booted once the Mac was OK again"

echo "== a run killed outright: its watcher shuts the device down and frees the slots"
reset
launch "$fixture/run.sh" "$fixture/r1" > /dev/null 2>&1 &
pid=$!
wait_booted "$fixture/r1"
sim=$(cat "$fixture/r1/sim")
kill -9 "$pid"; wait "$pid" 2>/dev/null || true
for _ in $(seq 100); do [[ "$(state "$sim")" == Shutdown && ! -f "$fixture/registry/$sim" ]] && break; sleep 0.1; done
[[ "$(state "$sim")" == Shutdown ]] || fail "SIGKILL: the watcher didn't shut the device down: $(cat "$STUB_LOG")"
[[ ! -f "$fixture/registry/$sim" ]] || fail "SIGKILL: registry entry left"
for _ in $(seq 50); do [[ -z "$(ls "$fixture/simlock" 2>/dev/null)" ]] && break; sleep 0.1; done
[[ -z "$(ls "$fixture/simlock" 2>/dev/null)" ]] || fail "SIGKILL: simulator slot left: $(ls "$fixture/simlock")"
# The killed run's test step (the stub) outlives it; stop it, and wait until it's gone.
pkill -TERM -f "$fixture/bin/xcodebuild" 2>/dev/null || true
for _ in $(seq 50); do pgrep -f "$fixture/bin/xcodebuild" >/dev/null 2>&1 || break; sleep 0.1; done
pass "SIGKILL: the watcher shut the device down, cleared the registry and the slot"

echo "== a slot whose run died without its watcher is taken over"
reset
mkdir -p "$fixture/simlock/slot-1"; echo 2147483000 > "$fixture/simlock/slot-1/pid"; echo /nowhere > "$fixture/simlock/slot-1/worktree"
CHATTERBOX_SIM_SLOTS=1 "$fixture/run.sh" "$fixture/r1" exit 2> "$fixture/r1.log"
grep -q "waiting" "$fixture/r1.log" && fail "waited on a dead run's slot: $(cat "$fixture/r1.log")"
check_clean stale "$fixture/r1"
pass "stale slot: taken over without waiting, given back"

echo "== a booted device whose run is gone (no watcher either): tidy --simulators shuts it down"
reset
sim=$(xcrun simctl create "Chatterbox test iPhone 26.2" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro); xcrun simctl boot "$sim"
mkdir -p "$fixture/registry"; printf 'pid 2147483000\nscript old-test.sh\n' > "$fixture/registry/$sim"
report=$("$root/scripts/tidy.sh" --simulators)
grep -q "Chatterbox test iPhone 26.2 ($sim) (Booted)" <<< "$report" || fail "tidy didn't report the orphan: $report"
grep -q "its run (pid 2147483000) is gone" <<< "$report" || fail "tidy didn't say why: $report"
"$root/scripts/tidy.sh" --simulators --apply > /dev/null
[[ "$(state "$sim")" == Shutdown ]] || fail "tidy --apply didn't shut the orphan down: $(cat "$STUB_LOG")"
[[ ! -f "$fixture/registry/$sim" ]] || fail "tidy --apply left the registry entry"
pass "orphan on record: tidy --simulators reports it and --apply shuts it down"

echo "== tidy keeps a booted device whose run is alive, and both shared devices when shut down"
reset
launch "$fixture/run.sh" "$fixture/r1" hold > /dev/null 2>&1 &
p1=$!
wait_booted "$fixture/r1"
launch "$fixture/run.sh" "$fixture/r2" hold > /dev/null 2>&1 &
p2=$!
wait_booted "$fixture/r2"
report=$("$root/scripts/tidy.sh" --simulators)
grep -q "keep (booted by test run pid $p1): Chatterbox test iPhone 26.2 (" <<< "$report" || fail "tidy didn't keep the first run's device: $report"
grep -q "keep (booted by test run pid $p2): Chatterbox test iPhone 26.2 #2 (" <<< "$report" || fail "tidy didn't keep the second run's device: $report"
touch "$fixture/r1/release" "$fixture/r2/release"; wait_gone "$p1" tidy-first; wait_gone "$p2" tidy-second
report=$("$root/scripts/tidy.sh" --simulators)
[[ "$(grep -c "keep (reusable test device)" <<< "$report")" == 2 ]] || fail "tidy didn't keep both shared devices: $report"
grep -q "simctl delete" "$STUB_LOG" && fail "tidy deleted a shared device"
pass "tidy: live runs kept; both shared devices kept for the next runs"
echo "All simulator hygiene checks passed."
