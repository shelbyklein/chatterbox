#!/bin/bash
# test-hygiene.sh and simulators: a test run that boots the shared test device shuts it down on
# every way out (exit, Ctrl-C, SIGTERM, SIGHUP) and gives the build slot back; a run killed
# outright leaves its device on record, and scripts/tidy.sh --simulators shuts it down. Runs
# against a stub `xcrun` that only logs what simctl was asked, so no simulator is touched.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
fixture=$(mktemp -d /tmp/chatterbox-test-hygiene-sims.XXXXXX)
export CHATTERBOX_BUILD_LOCK_DIR="$fixture/lock" CHATTERBOX_SIMULATOR_REGISTRY="$fixture/registry"
export STUB_LOG="$fixture/simctl.log" STUB_STATE="$fixture/state"
unset CHATTERBOX_BUILD_LOCK_HELD
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }

mkdir -p "$fixture/bin"
cat > "$fixture/bin/xcrun" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
udid=FA3E0000-0000-4000-8000-000000000001
case "$1 $2 $3" in
  "simctl list devices")
    if [[ " $* " == *" -j "* ]]; then
      if [[ "$(cat "$STUB_STATE" 2>/dev/null)" == *created* ]]; then
        state=Shutdown; [[ "$(tail -1 "$STUB_STATE")" == booted ]] && state=Booted
        echo "{\"devices\":{\"com.apple.CoreSimulator.SimRuntime.iOS-26-2\":[{\"name\":\"Chatterbox test iPhone 26.2\",\"udid\":\"$udid\",\"state\":\"$state\",\"deviceTypeIdentifier\":\"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro\",\"isAvailable\":true}]}}"
      else echo '{"devices":{}}'; fi
    else
      state=Shutdown; [[ "$(tail -1 "$STUB_STATE" 2>/dev/null)" == booted ]] && state=Booted
      printf '== Devices ==\n-- iOS 26.2 --\n    Chatterbox test iPhone 26.2 (%s) (%s) \n' "$udid" "$state"
    fi ;;
  "simctl list runtimes") echo '{"runtimes":[{"platform":"iOS","isAvailable":true,"version":"26.2","identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-2","supportedDeviceTypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"}]}]}' ;;
  "simctl create "*) echo created >> "$STUB_STATE"; echo "$udid" ;;
  "simctl boot "*) echo booted >> "$STUB_STATE" ;;
  "simctl shutdown "*) echo shutdown >> "$STUB_STATE" ;;
esac
exit 0
EOF
chmod +x "$fixture/bin/xcrun"
# A build step that takes a while, as xcodebuild test does.
printf '#!/bin/bash\nsleep 60\n' > "$fixture/bin/xcodebuild"; chmod +x "$fixture/bin/xcodebuild"
export PATH="$fixture/bin:$PATH"

# A test run: boots the device, tells us, then works until stopped.
cat > "$fixture/run.sh" <<EOF
#!/bin/bash
source "$root/scripts/lib/test-hygiene.sh"
set -euo pipefail
artifacts=\$(mktemp -d "$fixture/run.XXXXXX")
sim=\$(test_simulator iphone)
echo "\$sim" > "$fixture/sim"
echo "\$artifacts" > "$fixture/artifacts"
if [[ "\${1:-}" == exit ]]; then exit 0; fi
xcodebuild -destination "platform=iOS Simulator,id=\$sim" test
EOF
chmod +x "$fixture/run.sh"

# A background job of this script would have SIGINT ignored (and so untrappable); start runs
# the way a terminal does, with the default handlers.
launch() { exec /usr/bin/python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execv(sys.argv[1], sys.argv[1:])' "$@"; }
reset() { rm -f "$STUB_LOG" "$STUB_STATE" "$fixture/sim" "$fixture/artifacts"; rm -rf "$fixture/registry" "$fixture/lock"; }
wait_booted() { for _ in $(seq 100); do [[ -f "$fixture/sim" ]] && break; sleep 0.1; done; [[ -f "$fixture/sim" ]] || fail "the run never booted its device: $(cat "$STUB_LOG" 2>/dev/null)"; }
check_clean() {  # check_clean WAY
  local last; last=$(tail -1 "$STUB_STATE")
  [[ "$last" == shutdown ]] || fail "$1: the device wasn't shut down (state: $(tr '\n' ' ' < "$STUB_STATE"))"
  [[ -z "$(ls "$fixture/registry" 2>/dev/null)" ]] || fail "$1: registry entry left: $(ls "$fixture/registry")"
  [[ -z "$(ls "$fixture/lock" 2>/dev/null)" ]] || fail "$1: build slot left: $(ls "$fixture/lock")"
  grep -q "$(cat "$fixture/sim")" "$(cat "$fixture/artifacts")/simulators" || fail "$1: the artifact folder doesn't name the device"
}

echo "== a run that exits normally"
reset; "$fixture/run.sh" exit; check_clean exit
grep -q '^simctl create Chatterbox test iPhone 26.2 ' "$STUB_LOG" || fail "the device wasn't created under the shared name: $(cat "$STUB_LOG")"
pass "exit: device shut down, registry and slot clear, artifacts name the device"

echo "== the device is reused, not made again"
rm -f "$STUB_LOG" "$fixture/sim" "$fixture/artifacts"
"$fixture/run.sh" exit; check_clean reuse
grep -q 'simctl create' "$STUB_LOG" && fail "a second device was created: $(cat "$STUB_LOG")"
grep -q "simctl boot $(cat "$fixture/sim")" "$STUB_LOG" || fail "the existing device wasn't booted"
pass "reuse: the shut-down device was booted again, not created"

for sig in TERM INT HUP; do
  echo "== a run stopped with SIG$sig"
  reset
  launch "$fixture/run.sh" > "$fixture/run.$sig.log" 2>&1 &
  pid=$!
  wait_booted
  [[ -f "$fixture/registry/$(cat "$fixture/sim")" ]] || fail "$sig: no registry entry while booted"
  grep -q "^pid $pid$" "$fixture/registry/$(cat "$fixture/sim")" || fail "$sig: registry entry doesn't carry the run's pid"
  [[ -d "$fixture/lock/slot-1" ]] || fail "$sig: booting didn't take the build slot"
  kill -"$sig" "$pid"
  for _ in $(seq 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  kill -0 "$pid" 2>/dev/null && { kill -9 "$pid"; fail "$sig: the run didn't end"; }
  check_clean "$sig"
  pass "SIG$sig: device shut down, registry and slot clear"
done

echo "== a run killed outright: its watcher shuts the device down and frees the slot"
reset
launch "$fixture/run.sh" > /dev/null 2>&1 &
pid=$!
wait_booted
sim=$(cat "$fixture/sim")
kill -9 "$pid"; wait "$pid" 2>/dev/null || true
for _ in $(seq 100); do [[ "$(tail -1 "$STUB_STATE")" == shutdown && ! -f "$fixture/registry/$sim" ]] && break; sleep 0.1; done
[[ "$(tail -1 "$STUB_STATE")" == shutdown ]] || fail "SIGKILL: the watcher didn't shut the device down: $(cat "$STUB_LOG")"
[[ ! -f "$fixture/registry/$sim" ]] || fail "SIGKILL: registry entry left"
for _ in $(seq 50); do [[ -z "$(ls "$fixture/lock" 2>/dev/null)" ]] && break; sleep 0.1; done
[[ -z "$(ls "$fixture/lock" 2>/dev/null)" ]] || fail "SIGKILL: build slot left: $(ls "$fixture/lock")"
# The killed run's build step (the stub) outlives it; stop it, and wait until it's gone.
pkill -TERM -f "$fixture/bin/xcodebuild" 2>/dev/null || true
for _ in $(seq 50); do pgrep -f "$fixture/bin/xcodebuild" >/dev/null 2>&1 || break; sleep 0.1; done
pass "SIGKILL: the watcher shut the device down, cleared the registry and the slot"

echo "== a booted device whose run is gone (no watcher either): tidy --simulators shuts it down"
reset
mkdir -p "$fixture/registry"; echo created >> "$STUB_STATE"; echo booted >> "$STUB_STATE"
sim=FA3E0000-0000-4000-8000-000000000001
printf 'pid 2147483000\nscript old-test.sh\n' > "$fixture/registry/$sim"
report=$("$root/scripts/tidy.sh" --simulators)
grep -q "Chatterbox test iPhone 26.2 ($sim) (Booted)" <<< "$report" || fail "tidy didn't report the orphan: $report"
grep -q "its run (pid 2147483000) is gone" <<< "$report" || fail "tidy didn't say why: $report"
"$root/scripts/tidy.sh" --simulators --apply > /dev/null
[[ "$(tail -1 "$STUB_STATE")" == shutdown ]] || fail "tidy --apply didn't shut the orphan down: $(cat "$STUB_LOG")"
[[ ! -f "$fixture/registry/$sim" ]] || fail "tidy --apply left the registry entry"
pass "orphan on record: tidy --simulators reports it and --apply shuts it down"

echo "== tidy keeps a booted device whose run is alive, and the shared device when shut down"
reset
launch "$fixture/run.sh" > /dev/null 2>&1 &
pid=$!
wait_booted
report=$("$root/scripts/tidy.sh" --simulators)
# Its build step names the device, and its run is alive: kept for either reason.
grep -qE "keep \((a build or test targets it|booted by test run pid $pid)\): Chatterbox test iPhone" <<< "$report" || fail "tidy didn't keep the live run's device: $report"
kill -TERM "$pid"; wait "$pid" 2>/dev/null || true
report=$("$root/scripts/tidy.sh" --simulators)
grep -q "keep (reusable test device)" <<< "$report" || fail "tidy didn't keep the shared device: $report"
grep -q "simctl delete" "$STUB_LOG" && fail "tidy deleted the shared device"
pass "tidy: live run kept; the shared device is kept for the next run"
echo "All simulator hygiene checks passed."
