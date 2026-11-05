# Simulator slots: how many simulator test runs go at once across every checkout and worktree
# (AGENTS.md, "Build and test hygiene"). A phone suite builds under the build slot
# (build-lock.sh), gives it back, and then boots its device and runs its tests under one of
# these, so a second worktree's build or a second suite runs while the first one's XCUITests
# drive the app (mostly idle CPU).
#
# Sourced by test-hygiene.sh; test_simulator takes the slot, and the slot's number picks the
# device (slot 1 "Chatterbox test iPhone 26.2", slot 2 "… 26.2 #2"), so two runs never share a
# device and each still reuses its own run after run.
#
#   sim_lock            take a slot (held until the script exits); prints the waiting line
#   sim_unlock          give it back early
#   _sim_lock_number    the number of the slot held (after sim_lock)
#
#   CHATTERBOX_SIM_SLOTS=N       simulator runs at once (default 2)
#   CHATTERBOX_SIM_LOCK_DIR=…    where the slots live (default ~/Library/Caches/Chatterbox/simulator-lock)
#
# The Mac's pressure (~/Library/Caches/Chatterbox/pressure.json, written by the background
# service every 10 s; a file older than a minute is ignored), as for builds: while it's busy, one
# at a time (a run waits while any other holds a slot); while it's overloaded, no new run boots
# a device until it's less loaded (running ones carry on). CHATTERBOX_PRESSURE_FILE reads another file (tests);
# CHATTERBOX_BUILD_IGNORE_PRESSURE=1 ignores it.
#
# Slots are directories made with mkdir (atomic) holding the owner's pid and worktree, as the
# build slots are; a slot whose owner is gone (SIGKILL) is taken over by the next run.

_sim_lock_dir=${CHATTERBOX_SIM_LOCK_DIR:-$HOME/Library/Caches/Chatterbox/simulator-lock}
_sim_lock_slots=${CHATTERBOX_SIM_SLOTS:-2}
_sim_lock_number=''
if [[ -n "${BASH_SOURCE:-}" ]]; then _sim_lock_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
else eval '_sim_lock_root=$(cd "$(dirname "${(%):-%x}")/../.." && pwd)'; fi

_sim_lock_pid() { command cat "$1/pid" 2>/dev/null || true; }
_sim_lock_worktree() { command cat "$1/worktree" 2>/dev/null || true; }

_sim_lock_live() {  # a slot mid-creation (no pid yet, under 5 s old) counts as live
  local pid; pid=$(_sim_lock_pid "$1")
  if [[ -z "$pid" ]]; then
    local age; age=$(( $(date +%s) - $(stat -f %m "$1" 2>/dev/null || echo 0) ))
    (( age < 5 )); return
  fi
  kill -0 "$pid" 2>/dev/null
}

# The Mac's pressure level from pressure.json: ok (also when there's no fresh file), busy or
# overloaded.
_sim_lock_level() {
  [[ -n "${CHATTERBOX_BUILD_IGNORE_PRESSURE:-}" ]] && { echo ok; return; }
  local file=${CHATTERBOX_PRESSURE_FILE:-$HOME/Library/Caches/Chatterbox/pressure.json} level updated now
  [[ -f "$file" ]] || { echo ok; return; }
  level=$(command plutil -extract level raw -o - "$file" 2>/dev/null) || { echo ok; return; }
  updated=$(command plutil -extract updated raw -o - "$file" 2>/dev/null) || { echo ok; return; }
  [[ "$updated" =~ ^[0-9]+$ ]] || { echo ok; return; }
  now=$(date +%s)
  if (( now - updated <= 60 && updated - now <= 60 )) && [[ "$level" == busy || "$level" == overloaded ]]; then echo "$level"
  else echo ok; fi
}

_sim_lock_claim() {  # _sim_lock_claim N: make slot N ours
  printf '%s\n' "$$" > "$1/pid"; printf '%s\n' "$_sim_lock_root" > "$1/worktree"
}

_sim_lock_try() {  # one pass over the slots; sets _sim_lock_number on success
  local n slot slots=$_sim_lock_slots level=$1
  for (( n = 1; n <= slots; n++ )); do
    # Taken by this script already (test_simulator runs in a `$(…)` subshell): it's ours.
    if [[ "$(_sim_lock_pid "$_sim_lock_dir/slot-$n")" == "$$" ]]; then _sim_lock_number=$n; return 0; fi
  done
  [[ "$level" == overloaded ]] && return 1
  if [[ "$level" != ok ]]; then
    # Busy: one simulator run at a time, whatever slot the others hold.
    for (( n = 1; n <= slots; n++ )); do _sim_lock_live "$_sim_lock_dir/slot-$n" && return 1; done
  fi
  for (( n = 1; n <= slots; n++ )); do
    slot="$_sim_lock_dir/slot-$n"
    if command mkdir "$slot" 2>/dev/null; then _sim_lock_claim "$slot"; _sim_lock_number=$n; return 0; fi
    if ! _sim_lock_live "$slot"; then
      local stale="$_sim_lock_dir/stale-$n-$$"
      if command mv "$slot" "$stale" 2>/dev/null; then
        command rm -rf "$stale"
        if command mkdir "$slot" 2>/dev/null; then _sim_lock_claim "$slot"; _sim_lock_number=$n; return 0; fi
      fi
    fi
  done
  return 1
}

sim_lock() {
  command mkdir -p "$_sim_lock_dir"
  local waited=0 said='' line level n slot owners
  while :; do
    level=$(_sim_lock_level)
    _sim_lock_try "$level" && break
    owners=''
    for (( n = 1; n <= _sim_lock_slots; n++ )); do
      slot="$_sim_lock_dir/slot-$n"
      [[ -d "$slot" ]] && owners="$owners${owners:+; }pid $(_sim_lock_pid "$slot"), worktree $(_sim_lock_worktree "$slot")"
    done
    line="waiting for a simulator slot ($owners)"
    [[ "$level" == busy ]] && line="$line; the Mac is busy, so simulator runs go one at a time"
    [[ "$level" == overloaded ]] && line="waiting: the Mac is overloaded; new simulator runs wait until it's less loaded"
    if [[ "$line" != "$said" ]] || (( waited % 60 == 0 )); then echo "$line" >&2; said=$line; fi
    sleep 2; waited=$(( waited + 2 ))
  done
  [[ -n "$said" ]] && echo "simulator slot $_sim_lock_number free after ${waited}s" >&2
  return 0
}

sim_unlock() {  # every slot this script holds, a subshell's included
  local slot
  while IFS= read -r slot; do
    [[ -n "$slot" && -d "$slot" ]] || continue
    [[ "$(_sim_lock_pid "$slot")" == "$$" ]] && command rm -rf "$slot"
  done < <(command find "$_sim_lock_dir" -maxdepth 1 -name 'slot-*' 2>/dev/null)
  _sim_lock_number=''
  return 0
}
