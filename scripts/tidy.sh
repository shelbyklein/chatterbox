#!/bin/bash
# Lists what development work leaves behind, and with --apply removes it. Run it at the end of a
# session; /dev-sync runs it too. Nothing is removed without --apply, and nothing that a running
# process uses (or that hosts Claude/Codex chat work) is touched.
#
#   scripts/tidy.sh            report
#   scripts/tidy.sh --apply    remove what the report lists as removable
#
# Covered: leftover test processes, old test temp folders, stray app copies and one-off build
# folders, simulators made by tests, waiting restart jobs and old activation folders. Branches and
# worktrees are /dev-sync's job (its inventory reports them).
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/safe-stop.sh
apply=0; [[ " $* " == *" --apply "* ]] && apply=1
repo=$PWD
# The only build folders scripts may use (see AGENTS.md, "Build and test hygiene").
keep_builds="DerivedData DerivedDataMobile DerivedData-MobileTests runtime TestFlight"
day=$((24*3600)); now=$(date +%s)
removable=0; kept=0; other_apps=0

age() { echo $(( (now - $(stat -f %m "$1")) / day )); }
# What running processes use, gathered once: their command lines, working folders and
# executables. A path is in use if any of them is at or under it.
used=$( { ps -axo command=; lsof -nP -d cwd,txt -Fn 2>/dev/null | sed -n 's/^n//p'; } | sort -u)
in_use() { grep -qF -- "$1" <<< "$used"; }
verbose=0; [[ " $* " == *" --verbose "* ]] && verbose=1
section_count=0; section_kb=0
item() { printf '  - %s\n' "$*"; }
# Each section shows its first few entries, then a count and total size.
listed() { section_count=$((section_count+1)); (( verbose || section_count <= 5 )) && item "$@"; true; }
remove() {  # remove PATH "why"
  removable=$((removable+1))
  section_kb=$((section_kb + $(du -sk "$1" 2>/dev/null | cut -f1)))
  listed "$2: $1"
  (( apply )) && rm -rf "$1"
  true
}
keep() { kept=$((kept+1)); item "keep ($2): $1"; }
section() {
  if (( section_count > 5 && ! verbose )); then item "…and $((section_count-5)) more (--verbose lists all)"; fi
  (( section_count )) && printf '  %d item(s), %s MB\n' "$section_count" $((section_kb/1024))
  section_count=0; section_kb=0
  [[ -n "${1:-}" ]] && echo "== $1"
  true
}

section "Leftover test processes (fake agents and services whose test is gone)"
while read -r pid ppid cmd; do
  [[ -n "$pid" ]] || continue
  if [[ -n "$(hosted_work "$pid")" ]]; then keep "$pid $cmd" "hosts chat work"; continue; fi
  removable=$((removable+1)); listed "pid $pid: ${cmd:0:120}"
  (( apply )) && safe_stop "$pid"
done < <(ps -axo pid=,ppid=,command= | awk '$2==1' \
  | grep -E '/tmp/[^ ]*/fake-provider|fake-provider.py|/tmp/(golem|chatterbox|canvas)-[^ ]*/(chatterboxd|ChatterboxHost|test)( |$)' \
  | grep -v grep || true)

section "Test temp folders older than 2 days"
for d in /tmp/chatterbox-* /tmp/golem-* /tmp/canvas-* /tmp/test-hygiene.* /private/tmp/merge-check.*; do
  [[ -e "$d" ]] || continue
  [[ $(age "$d") -ge 2 ]] || continue
  if in_use "$d"; then keep "$d" "in use"; else remove "$d" "temp folder, $(age "$d") days old"; fi
done

section "One-off build folders in build/ (only $keep_builds are kept)"
for d in build/*/; do
  name=$(basename "$d")
  [[ " $keep_builds " == *" $name "* ]] && continue
  if in_use "$repo/$d"; then keep "$d" "in use"; else remove "$d" "one-off build folder, $(du -sh "$d" 2>/dev/null | cut -f1)"; fi
done

section "App copies outside /Applications and the kept build folders"
while IFS= read -r app; do
  [[ -n "$app" ]] || continue
  # build/ is covered by the section above (kept folders hold the one real build each).
  case "$app" in "$repo/build/"*) continue ;; esac
  [[ -e "$app" ]] || continue
  if in_use "$app/"; then keep "$app" "running"; continue; fi
  case "$app" in
    /tmp/*|/private/tmp/*) remove "$app" "app copy" ;;
    *) other_apps=$((other_apps+1)) ;;
  esac
done < <( { find /tmp /private/tmp -maxdepth 6 \( -name Chatterbox.app -o -name Golem.app \) -type d -prune 2>/dev/null
            find "$HOME/Vibes" -maxdepth 7 -path '*/node_modules' -prune -o \( -name Chatterbox.app -o -name Golem.app \) -type d -prune -print 2>/dev/null; } | sort -u)

(( other_apps )) && item "$other_apps app copies in other repos' build folders (e.g. Golem); left for that repo's own cleanup"

section "Simulators made by tests"
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  udid=$(sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' <<< "$line")
  if [[ "$line" == *"(Booted)"* ]]; then keep "$line" "booted"; continue; fi
  removable=$((removable+1)); listed "simulator: $line"
  (( apply )) && xcrun simctl delete "$udid" >/dev/null 2>&1
  true
done < <(xcrun simctl list devices 2>/dev/null \
  | grep -E 'Golem separation|Chatterbox|regression|remediation|lane-[a-z]-|tt-|TT Website' | sed -E 's/^ +//')

section "Restart jobs and activation folders"
for pid in $(pgrep -f 'restart-service.sh|Activation/activate.sh|cb-restart.sh' 2>/dev/null); do
  item "waiting restart job, pid $pid: $(ps -o command= -p "$pid" | cut -c1-100)  (scripts/restart-service.sh replaces it)"
done
for d in "$HOME/Library/Application Support/"*-Activation "$HOME/Library/Application Support/Chatterbox-Version-Archive"/*; do
  [[ -d "$d" ]] || continue
  [[ $(age "$d") -ge 7 ]] && remove "$d" "old activation/archive folder, $(age "$d") days" || true
done

section "Xcode's own Chatterbox/Golem build data older than 14 days (other projects are left alone)"
for d in "$HOME/Library/Developer/Xcode/DerivedData"/Chatterbox-* "$HOME/Library/Developer/Xcode/DerivedData"/Golem-*; do
  [[ -d "$d" ]] || continue
  [[ $(age "$d") -ge 14 ]] && remove "$d" "Xcode DerivedData, $(age "$d") days old" || true
done

section
echo
if (( apply )); then echo "Removed $removable item(s); kept $kept."
else echo "$removable removable, $kept kept. Run scripts/tidy.sh --apply to remove them."; fi
