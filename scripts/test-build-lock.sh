#!/bin/bash
# The shared build lock (scripts/lib/build-lock.sh): two builds serialize, a slot whose owner
# died is taken over, a slot taken in a subshell is the script's own, two slots let two builds
# run, the xcodebuild wrapper caps -jobs, and the Mac's pressure (pressure.json, written by the
# service) holds builds to one at a time when busy and makes new ones wait when overloaded, a
# stale file being ignored. Runs against a private lock folder, pressure file and stub tools.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
fixture=$(mktemp -d /tmp/chatterbox-test-build-lock.XXXXXX)
export CHATTERBOX_BUILD_LOCK_DIR="$fixture/lock"
# Never the Mac's own pressure file: these checks write their own.
export CHATTERBOX_PRESSURE_FILE="$fixture/pressure.json"
unset CHATTERBOX_BUILD_IGNORE_PRESSURE
unset CHATTERBOX_BUILD_LOCK_HELD
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }
stamp() { /usr/bin/python3 -c 'import time; print(f"{time.time():.3f}")'; }

# A "build": logs when it starts and ends, under the lock.
cat > "$fixture/worker.sh" <<EOF
#!/bin/bash
set -euo pipefail
source "$root/scripts/lib/build-lock.sh"
with_build_lock bash -c 'echo "start \$1 \$(/usr/bin/python3 -c "import time; print(f\"{time.time():.3f}\")")" >> "\$2"; sleep "\$3"; echo "end \$1 \$(/usr/bin/python3 -c "import time; print(f\"{time.time():.3f}\")")" >> "\$2"' _ "\$1" "\$2" "\${3:-1.5}"
EOF
chmod +x "$fixture/worker.sh"

overlap() {  # overlap LOG → "yes" when the two runs overlapped
  /usr/bin/python3 - "$1" <<'PY'
import sys
runs = {}
for line in open(sys.argv[1]):
    kind, name, t = line.split()
    runs.setdefault(name, {})[kind] = float(t)
a, b = runs["A"], runs["B"]
print("yes" if a["start"] < b["end"] and b["start"] < a["end"] else "no")
PY
}

echo "== two builds take turns"
log="$fixture/serial.log"
CHATTERBOX_BUILD_SLOTS=1 "$fixture/worker.sh" A "$log" 1.5 2> "$fixture/A.err" &
a=$!
sleep 0.3
CHATTERBOX_BUILD_SLOTS=1 "$fixture/worker.sh" B "$log" 0.5 2> "$fixture/B.err" &
b=$!
wait "$a" "$b"
[[ "$(overlap "$log")" == no ]] || fail "the two builds overlapped: $(cat "$log")"
grep -q "waiting for another build (pid $a, worktree $root)" "$fixture/B.err" || fail "B didn't say it was waiting for A: $(cat "$fixture/B.err")"
[[ -z "$(ls "$fixture/lock" 2>/dev/null)" ]] || fail "slots left behind: $(ls "$fixture/lock")"
pass "one slot: the second build waited for the first, said so, and both slots were given back"

echo "== a slot whose owner died is taken over"
mkdir -p "$fixture/lock/slot-1"; echo 2147483000 > "$fixture/lock/slot-1/pid"; echo /nowhere > "$fixture/lock/slot-1/worktree"
before=$(stamp)
CHATTERBOX_BUILD_SLOTS=1 "$fixture/worker.sh" C "$fixture/stale.log" 0.1 2> "$fixture/C.err"
after=$(stamp)
/usr/bin/python3 -c 'import sys; a,b=map(float,sys.argv[1:]); sys.exit(0 if b-a < 5 else 1)' "$before" "$after" || fail "took over $(cat "$fixture/C.err")"
[[ ! -d "$fixture/lock/slot-1" ]] || fail "the taken-over slot wasn't given back"
pass "stale slot: taken over without waiting, then given back"

echo "== a slot taken in a subshell is the script's own"
cat > "$fixture/subshell.sh" <<EOF
#!/bin/bash
set -euo pipefail
source "$root/scripts/lib/build-lock.sh"
got=\$(build_lock; echo got)
[[ -d "$fixture/lock/slot-1" ]] || { echo "the subshell didn't take the slot" >&2; exit 1; }
with_build_lock true
echo "\$got released"
EOF
chmod +x "$fixture/subshell.sh"
( CHATTERBOX_BUILD_SLOTS=1 "$fixture/subshell.sh" > "$fixture/subshell.out" 2>&1 & pid=$!
  for _ in $(seq 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; echo hung > "$fixture/subshell.out"; fi )
grep -q "got released" "$fixture/subshell.out" || fail "subshell slot: $(cat "$fixture/subshell.out")"
[[ -z "$(ls "$fixture/lock" 2>/dev/null)" ]] || fail "subshell slot left behind: $(ls "$fixture/lock")"
pass "subshell: the slot it took is adopted, not waited on, and given back on exit"

echo "== two slots let two builds run at once"
log="$fixture/parallel.log"
CHATTERBOX_BUILD_SLOTS=2 "$fixture/worker.sh" A "$log" 1.5 &
a=$!
sleep 0.3
CHATTERBOX_BUILD_SLOTS=2 "$fixture/worker.sh" B "$log" 0.5 &
b=$!
wait "$a" "$b"
[[ "$(overlap "$log")" == yes ]] || fail "two slots still serialized: $(cat "$log")"
pass "two slots: both builds ran together"

# pressure LEVEL [AGE]: the service's file, written AGE seconds ago (default now).
pressure() {
  local updated=$(( $(date +%s) - ${2:-0} ))
  printf '{"level":"%s","updated":%s,"updatedAt":"x","summary":"load 52 on 16 cores (over 3\u00d7) for 1 min"}' "$1" "$updated" > "$CHATTERBOX_PRESSURE_FILE.tmp"
  mv "$CHATTERBOX_PRESSURE_FILE.tmp" "$CHATTERBOX_PRESSURE_FILE"
}

echo "== busy: one build at a time, even with two slots"
pressure busy
log="$fixture/busy.log"
CHATTERBOX_BUILD_SLOTS=2 "$fixture/worker.sh" A "$log" 1.5 2> "$fixture/busyA.err" &
a=$!
sleep 0.3
CHATTERBOX_BUILD_SLOTS=2 "$fixture/worker.sh" B "$log" 0.5 2> "$fixture/busyB.err" &
b=$!
wait "$a" "$b"
[[ "$(overlap "$log")" == no ]] || fail "busy: two builds overlapped: $(cat "$log")"
grep -q "waiting for another build (pid $a, worktree $root); the Mac is busy (load 52 on 16 cores" "$fixture/busyB.err" || fail "busy: B's waiting line: $(cat "$fixture/busyB.err")"
pass "busy: two slots allowed, but the second build waited, saying the Mac is busy"

echo "== overloaded: a new build waits; a running one carries on"
rm -f "$CHATTERBOX_PRESSURE_FILE"
log="$fixture/over.log"
"$fixture/worker.sh" A "$log" 3 2> "$fixture/overA.err" &
a=$!
sleep 0.5
pressure overloaded
"$fixture/worker.sh" B "$log" 0.2 2> "$fixture/overB.err" &
b=$!
sleep 4
grep -q "end A" "$log" || fail "overloaded: the running build didn't carry on: $(cat "$log")"
! grep -q "start B" "$log" || fail "overloaded: B started anyway: $(cat "$log")"
grep -q "waiting: the Mac is overloaded (load 52 on 16 cores" "$fixture/overB.err" || fail "overloaded: B's waiting line: $(cat "$fixture/overB.err")"
pressure busy
wait "$b"
grep -q "end B" "$log" || fail "overloaded: B never ran once the Mac was busy: $(cat "$log")"
grep -q "build slot free after" "$fixture/overB.err" || fail "B didn't say when it got its slot"
[[ -z "$(ls "$fixture/lock" 2>/dev/null)" ]] || fail "overloaded: slots left behind"
pass "overloaded: A finished, B waited (saying why) while overloaded and built once the Mac was only busy"

echo "== a stale pressure file is ignored"
pressure overloaded 120
log="$fixture/stale-pressure.log"
CHATTERBOX_BUILD_SLOTS=2 "$fixture/worker.sh" A "$log" 1.5 2> "$fixture/staleA.err" &
a=$!
sleep 0.3
CHATTERBOX_BUILD_SLOTS=2 "$fixture/worker.sh" B "$log" 0.5 2> "$fixture/staleB.err" &
b=$!
wait "$a" "$b"
[[ "$(overlap "$log")" == yes ]] || fail "stale: the two-minute-old file still held builds: $(cat "$log")"
! grep -q "overloaded\|busy" "$fixture/staleA.err" "$fixture/staleB.err" || fail "stale: a waiting line mentions pressure"
pressure overloaded
CHATTERBOX_BUILD_IGNORE_PRESSURE=1 "$fixture/worker.sh" C "$fixture/ignore.log" 0.1 2> "$fixture/ignore.err"
grep -q "end C" "$fixture/ignore.log" || fail "CHATTERBOX_BUILD_IGNORE_PRESSURE didn't build"
rm -f "$CHATTERBOX_PRESSURE_FILE"
pass "stale (2 min old): ignored, two slots ran together; CHATTERBOX_BUILD_IGNORE_PRESSURE=1 builds while overloaded"

echo "== xcodebuild gets -jobs capped; export and queries don't"
mkdir -p "$fixture/bin"
printf '#!/bin/bash\necho "$*"\n' > "$fixture/bin/xcodebuild"; chmod +x "$fixture/bin/xcodebuild"
jobs_line=$(PATH="$fixture/bin:$PATH" CHATTERBOX_COMPILE_CACHE=0 bash -c "source '$root/scripts/lib/build-lock.sh'; xcodebuild -scheme Chatterbox build")
cores=$(sysctl -n hw.ncpu); half=$(( cores / 2 )); (( half < 2 )) && half=2
[[ "$jobs_line" == "-jobs $half -scheme Chatterbox build" ]] || fail "build got: $jobs_line"
export_line=$(PATH="$fixture/bin:$PATH" bash -c "source '$root/scripts/lib/build-lock.sh'; xcodebuild -exportArchive -archivePath x")
[[ "$export_line" == "-exportArchive -archivePath x" ]] || fail "export got: $export_line"
chosen=$(PATH="$fixture/bin:$PATH" CHATTERBOX_COMPILE_CACHE=0 CHATTERBOX_BUILD_JOBS=3 bash -c "source '$root/scripts/lib/build-lock.sh'; xcodebuild build")
[[ "$chosen" == "-jobs 3 build" ]] || fail "CHATTERBOX_BUILD_JOBS got: $chosen"
pressure busy
quarter=$(( cores / 4 )); (( quarter < 2 )) && quarter=2
busy_line=$(PATH="$fixture/bin:$PATH" bash -c "source '$root/scripts/lib/build-lock.sh'; xcodebuild build")
rm -f "$CHATTERBOX_PRESSURE_FILE"
[[ "$busy_line" == "-jobs $quarter build" ]] || fail "busy build got: $busy_line"
pass "xcodebuild: -jobs $half added to builds ($quarter while the Mac is busy), not to -exportArchive; CHATTERBOX_BUILD_JOBS wins"

echo "== builds use the shared compilation cache, with this checkout's root mapped"
cached=$(PATH="$fixture/bin:$PATH" bash -c "source '$root/scripts/lib/build-lock.sh'; xcodebuild -scheme Chatterbox build")
for want in COMPILATION_CACHE_ENABLE_CACHING=YES "COMPILATION_CACHE_CAS_PATH=$HOME/Library/Caches/Chatterbox/CompilationCache" \
    SWIFT_ENABLE_PREFIX_MAPPING=YES "SWIFT_OTHER_PREFIX_MAPPINGS=$root=/^wt" "CLANG_OTHER_PREFIX_MAPPINGS=$root=/^wt"; do
  [[ " $cached " == *" $want "* ]] || fail "build lacks $want: $cached"
done
z=$(PATH="$fixture/bin:$PATH" zsh -c "source '$root/scripts/lib/build-lock.sh'; xcodebuild build")
[[ " $z " == *" COMPILATION_CACHE_ENABLE_CACHING=YES "* ]] || fail "zsh build lacks the cache: $z"
export_line=$(PATH="$fixture/bin:$PATH" bash -c "source '$root/scripts/lib/build-lock.sh'; xcodebuild -exportArchive -archivePath x")
[[ "$export_line" == "-exportArchive -archivePath x" ]] || fail "export got cache settings: $export_line"
own=$(PATH="$fixture/bin:$PATH" bash -c "source '$root/scripts/lib/build-lock.sh'; xcodebuild build COMPILATION_CACHE_ENABLE_CACHING=NO")
[[ "$own" == "-jobs $half build COMPILATION_CACHE_ENABLE_CACHING=NO" ]] || fail "a build's own cache setting overridden: $own"
pass "compilation cache: on for builds (bash and zsh), off for -exportArchive, a build's own setting and CHATTERBOX_COMPILE_CACHE=0"

echo "== zsh runs it too (install.sh)"
z=$(PATH="$fixture/bin:$PATH" CHATTERBOX_COMPILE_CACHE=0 CHATTERBOX_BUILD_SLOTS=1 zsh -c "source '$root/scripts/lib/build-lock.sh'; xcodebuild build; ls '$fixture/lock'")
[[ "$z" == "-jobs $half build" ]] || fail "zsh got: $z"
pass "zsh: the wrapper and the lock work, slot given back"
echo "All build lock checks passed."
