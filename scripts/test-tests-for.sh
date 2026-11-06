#!/bin/bash
# scripts/tests-for.sh on known changes: each set of changed files maps to the tests that cover
# them, and not to tests that only happen to compile them.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL $*"; exit 1; }

# expect "FILES…" -- tests that must be listed -- ! tests that must not be
expect() {
  local files=() want=() unwanted=() mode=files arg out
  for arg in "$@"; do
    case "$arg" in
      --) mode=want ;;
      !) mode=unwanted ;;
      *) case $mode in files) files+=("$arg") ;; want) want+=("$arg") ;; unwanted) unwanted+=("$arg") ;; esac ;;
    esac
  done
  out=$(scripts/tests-for.sh "${files[@]}")
  for arg in ${want[@]+"${want[@]}"}; do
    grep -qx "scripts/$arg" <<<"$out" || fail "${files[*]}: missing $arg in: $(echo $out)"
  done
  for arg in ${unwanted[@]+"${unwanted[@]}"}; do
    grep -qx "scripts/$arg" <<<"$out" && fail "${files[*]}: listed $arg"
  done
  echo "PASS ${files[*]} -> $(echo "$out" | sed 's|scripts/||' | tr '\n' ' ')"
}

# A type a test uses, given as Core/… or the checkout's own path.
expect Core/Chatterbox/Engine/DeskStore.swift -- test-desk.sh test-work-threads.sh ! test-pdf-flip.sh test-chat-find.sh
expect Chatterbox/Engine/DeskStore.swift -- test-desk.sh
# A file of extensions: the functions it adds.
expect Core/Chatterbox/Engine/ChatSession+Work.swift -- test-work-threads.sh ! test-desk.sh
expect Core/ChatterboxRuntime/SimulatorSweep.swift -- test-simulator-sweeper.sh ! test-desk.sh
# Named by the script; the test itself; its own folder.
expect scripts/lib/safe-stop.sh -- test-host-handoff.sh ! test-desk.sh
expect scripts/test-desk.sh -- test-desk.sh ! test-work-threads.sh
expect tests/desk/main.swift -- test-desk.sh ! test-work-threads.sh
expect ChatterboxMobile/MobileComposerDraft.swift -- test-mobile-composer.sh ! test-desk.sh
# scripts/test-map.txt, and check-sources.sh for project changes.
expect ChatterboxHost/Host.swift -- test-host-handoff.sh test-host-upgrade.sh ! test-desk.sh
expect project.yml -- check-sources.sh test-flavor.sh
expect scripts/tests-for.sh -- test-tests-for.sh
# Several at once: the union.
expect scripts/lib/safe-stop.sh tests/desk/main.swift -- test-host-handoff.sh test-desk.sh
# Nothing covers a README.
[[ -z "$(scripts/tests-for.sh README.md)" ]] || fail "README.md listed tests"
echo "PASS README.md -> (none)"

all=$(scripts/tests-for.sh --all | wc -l | tr -d ' ')
[[ "$all" == "$(ls scripts/test-*.sh | wc -l | tr -d ' ')" ]] || fail "--all listed $all"
echo "PASS --all lists every test script ($all)"
why=$(scripts/tests-for.sh --why Core/Chatterbox/Engine/DeskStore.swift)
grep -q 'uses DeskStore' <<<"$why" || fail "--why gave no reason"
echo "PASS --why gives reasons"
python3 tests/tests-for/main.py
echo "tests-for: all passed"
