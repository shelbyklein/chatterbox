#!/bin/bash
# The shared build lock (scripts/lib/build-lock.sh): two builds serialize, a slot whose owner
# died is taken over, a slot taken in a subshell is the script's own, two slots let two builds
# run, and the xcodebuild wrapper caps -jobs. Runs against a private lock folder and stub tools.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
fixture=$(mktemp -d /tmp/chatterbox-test-build-lock.XXXXXX)
export CHATTERBOX_BUILD_LOCK_DIR="$fixture/lock"
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
pass "xcodebuild: -jobs $half added to builds, not to -exportArchive; CHATTERBOX_BUILD_JOBS wins"

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
