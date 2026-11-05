#!/bin/bash
# Warm-start a new worktree: clone the main checkout's build folders into it, so its first
# builds pick up where the main checkout's left off instead of starting from nothing (AGENTS.md,
# "Build and test hygiene").
#
#   scripts/warm-worktree.sh [WORKTREE]   clone into WORKTREE (default: the checkout you're in)
#   scripts/warm-worktree.sh --install-hook
#                                         make `git worktree add` do it by itself (a post-checkout
#                                         hook in the shared .git/hooks; once per clone)
#
#   --from DIR   clone from DIR's build folders (default: the main checkout)
#   --force      replace build folders the worktree already has (default: keep them)
#
# The clones are APFS copy-on-write (clonefile: `cp -c`): no extra disk until either side
# changes a file, and seconds rather than minutes. Cloned: build/DerivedData,
# DerivedDataMobile, DerivedData-MobileTests, DerivedData-Dev, DerivedDataMobile-Dev and runtime,
# whichever exist. Left behind: every app bundle (each copy is one more Chatterbox macOS offers),
# Logs and TestResults, and everything else in build/ (logs, screenshots, per-run temp folders).
# Xcode rebuilds the app bundles from the cloned intermediates in seconds.
#
# Waits while the main checkout is itself building (its build slot), so it never clones a
# half-written build. Never fails a `git worktree add`: from the hook, problems are reported and
# the worktree is left as git made it.
set -uo pipefail

FOLDERS=(DerivedData DerivedDataMobile DerivedData-MobileTests DerivedData-Dev DerivedDataMobile-Dev runtime)
SKIP_NAMES=(Logs TestResults)   # top level of a DerivedData folder

say() { echo "warm-worktree: $*" >&2; }

from='' force=0 hook=0 install=0 target=''
while (( $# )); do
  case "$1" in
    --from) from=$2; shift 2 ;;
    --force) force=1; shift ;;
    --hook) hook=1; shift ;;
    --install-hook) install=1; shift ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) say "unknown option $1"; exit 2 ;;
    *) target=$1; shift ;;
  esac
done

# --- The hook ---------------------------------------------------------------------------------

HOOK_MARK='# chatterbox-warm-worktree'
if (( install )); then
  hooks=$(git rev-parse --git-path hooks 2>/dev/null) || { say "not in a git checkout"; exit 1; }
  hooks=$(cd "$hooks" 2>/dev/null && pwd) || { mkdir -p "$hooks"; hooks=$(cd "$hooks" && pwd); }
  hook_file="$hooks/post-checkout"
  if [[ -f "$hook_file" ]] && ! grep -q "$HOOK_MARK" "$hook_file"; then
    say "$hook_file exists and isn't ours; add this to it by hand:"
    say '  sh "$(git rev-parse --show-toplevel)/scripts/warm-worktree.sh" --hook "$@"'
    exit 1
  fi
  cat > "$hook_file" <<EOF
#!/bin/sh
$HOOK_MARK: \`git worktree add\` checks out with a null previous HEAD; warm the new worktree's
# build folders from the main checkout (scripts/warm-worktree.sh, AGENTS.md). Never fails.
case "\$1" in *[!0]*) exit 0 ;; esac
top=\$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "\$top/scripts/warm-worktree.sh" ] || exit 0
/bin/bash "\$top/scripts/warm-worktree.sh" --hook "\$top" || true
exit 0
EOF
  chmod +x "$hook_file"
  say "installed $hook_file"
  exit 0
fi

# --- Where from, where to ---------------------------------------------------------------------

if [[ -z "$target" ]]; then
  target=$(git rev-parse --show-toplevel 2>/dev/null) || { say "not in a git checkout"; exit 1; }
fi
target=$(cd "$target" 2>/dev/null && pwd -P) || { say "no folder $target"; exit 1; }

if [[ -z "$from" ]]; then
  # The main checkout: the one whose .git is the shared (common) git folder.
  common=$(git -C "$target" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { say "$target isn't a git checkout"; exit 1; }
  from=$(dirname "$common")
fi
from=$(cd "$from" 2>/dev/null && pwd -P) || { say "no folder $from"; exit 1; }

if [[ "$from" == "$target" ]]; then
  (( hook )) || say "$target is the main checkout; nothing to do"
  exit 0
fi

# --- Wait while the main checkout builds ------------------------------------------------------

lock_dir=${CHATTERBOX_BUILD_LOCK_DIR:-$HOME/Library/Caches/Chatterbox/build-lock}
building() {  # a live build slot owned by the main checkout
  local slot pid
  for slot in "$lock_dir"/slot-*; do
    [[ -d "$slot" ]] || continue
    [[ "$(cat "$slot/worktree" 2>/dev/null)" == "$from" ]] || continue
    pid=$(cat "$slot/pid" 2>/dev/null) && [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && return 0
  done
  return 1
}
waited=0 wait_limit=${CHATTERBOX_WARM_WAIT:-900}
while building; do
  (( waited == 0 )) && say "waiting for the build in $from to finish"
  if (( waited >= wait_limit )); then say "still building after ${waited}s; not warming"; exit 0; fi
  sleep 2; waited=$(( waited + 2 ))
done

# --- Cloning ----------------------------------------------------------------------------------

# clone SRC DST SKIPFILE: copy-on-write SRC to DST, leaving out the paths listed in SKIPFILE
# (absolute paths under SRC). Only folders holding a skipped path are walked; the rest go in one
# clonefile each.
clone() {
  local src=$1 dst=$2 skip=$3 entry
  if grep -qxF "$src" "$skip"; then return 0; fi
  if [[ -d "$src" && ! -L "$src" ]] && grep -qF "$src/" "$skip"; then
    mkdir -p "$dst"
    for entry in "$src"/* "$src"/.[!.]*; do
      [[ -e "$entry" || -L "$entry" ]] || continue
      clone "$entry" "$dst/${entry##*/}" "$skip" || return 1
    done
    return 0
  fi
  cp -c -R -p "$src" "$dst" 2>/dev/null || cp -R -p "$src" "$dst"
}

skip=$(mktemp /tmp/warm-worktree.XXXXXX)
trap 'rm -f "$skip"' EXIT
start=$(date +%s)
warmed=()
for folder in "${FOLDERS[@]}"; do
  src="$from/build/$folder" dst="$target/build/$folder"
  [[ -d "$src" ]] || continue
  if [[ -e "$dst" ]]; then
    if (( ! force )); then say "keeping the worktree's own build/$folder"; continue; fi
    rm -rf "$dst"
  fi
  mkdir -p "$target/build"
  : > "$skip"
  for name in "${SKIP_NAMES[@]}"; do [[ -e "$src/$name" ]] && printf '%s\n' "$src/$name" >> "$skip"; done
  find "$src" -name '*.app' \( -type d -o -type l \) -prune >> "$skip" 2>/dev/null
  # Into a temp name first, so a clone cut short never looks like a build folder.
  partial="$target/build/.$folder.warming"
  rm -rf "$partial"
  if clone "$src" "$partial" "$skip" && mv "$partial" "$dst"; then
    warmed+=("$folder")
  else
    say "couldn't clone build/$folder"; rm -rf "$partial"
  fi
done

if (( ${#warmed[@]} )); then
  say "cloned ${warmed[*]} from $from in $(( $(date +%s) - start ))s (copy-on-write)"
else
  say "nothing to clone from $from/build"
fi
exit 0
