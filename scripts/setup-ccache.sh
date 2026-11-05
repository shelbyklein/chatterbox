#!/bin/bash
# ccache for every C and C++ build on this Mac (AGENTS.md, "Build and test hygiene"): CMake
# projects (DiscusSlicer, say) compile through ccache, so a rebuild, a fresh build folder or a
# second checkout compiles only what changed instead of everything.
#
#   scripts/setup-ccache.sh           install ccache if missing (Homebrew), configure its cache,
#                                     and put the environment below in ~/.zshenv (every zsh: agent
#                                     shells, Terminal). Safe to run again.
#   scripts/setup-ccache.sh --check   say what's set up, change nothing
#
# The environment:
#   CCACHE_DIR=~/Library/Caches/ccache   CCACHE_MAXSIZE=20G
#   CMAKE_C_COMPILER_LAUNCHER / CMAKE_CXX_COMPILER_LAUNCHER = ccache
# CMake reads the launcher variables only when it first configures a build folder: an existing
# folder needs one reconfigure (cmake -DCMAKE_CXX_COMPILER_LAUNCHER=ccache …, or a fresh folder).
# Xcode builds don't use them. `ccache -s` shows hits and misses.
set -euo pipefail

ZSHENV=${CHATTERBOX_ZSHENV:-$HOME/.zshenv}
CACHE_DIR="$HOME/Library/Caches/ccache"
BEGIN='# >>> ccache (Chatterbox scripts/setup-ccache.sh) >>>'
END='# <<< ccache <<<'

ccache_bin() { command -v ccache 2>/dev/null || { [[ -x /opt/homebrew/bin/ccache ]] && echo /opt/homebrew/bin/ccache; } || true; }

if [[ "${1:-}" == --check ]]; then
  bin=$(ccache_bin)
  echo "ccache: ${bin:-not installed}${bin:+ ($("$bin" --version | head -1))}"
  if grep -qF "$BEGIN" "$ZSHENV" 2>/dev/null; then echo "environment: in $ZSHENV"; else echo "environment: not in $ZSHENV"; fi
  [[ -n "$bin" ]] && CCACHE_DIR="$CACHE_DIR" "$bin" -s 2>/dev/null | sed 's/^/  /' || true
  exit 0
fi

bin=$(ccache_bin)
if [[ -z "$bin" ]]; then
  echo "Installing ccache with Homebrew…"
  brew install ccache
  bin=$(ccache_bin)
fi
[[ -n "$bin" ]] || { echo "setup-ccache: ccache didn't install" >&2; exit 1; }

# The cache's own settings, so every run agrees whatever its environment. Precompiled headers
# (target_precompile_headers) are cacheable only with these sloppiness options.
mkdir -p "$CACHE_DIR"
CCACHE_DIR="$CACHE_DIR" "$bin" --set-config=max_size=20G
CCACHE_DIR="$CACHE_DIR" "$bin" --set-config=sloppiness=pch_defines,time_macros

block=$(cat <<EOF
$BEGIN
# Every C/C++ compile CMake configures goes through ccache (a build folder configured before
# this needs one reconfigure). Remove this block to turn it off.
if [ -x "$bin" ]; then
  export CCACHE_DIR="\$HOME/Library/Caches/ccache" CCACHE_MAXSIZE=20G
  export CMAKE_C_COMPILER_LAUNCHER="$bin" CMAKE_CXX_COMPILER_LAUNCHER="$bin"
fi
$END
EOF
)
touch "$ZSHENV"
if grep -qF "$BEGIN" "$ZSHENV"; then
  # Replace our block (it moves to the end), leaving the rest of the file as it is.
  tmp=$(mktemp "$ZSHENV.XXXXXX")
  awk -v b="$BEGIN" -v e="$END" '
    $0 == b { skip = 1; next }
    skip && $0 == e { skip = 0; next }
    !skip { print }' "$ZSHENV" > "$tmp"
  printf '%s\n' "$block" >> "$tmp"
  cat "$tmp" > "$ZSHENV"; rm -f "$tmp"
  echo "Updated the ccache block in $ZSHENV"
else
  { [[ -s "$ZSHENV" ]] && echo; printf '%s\n' "$block"; } >> "$ZSHENV"
  echo "Added the ccache block to $ZSHENV"
fi
echo "ccache: $bin ($("$bin" --version | head -1)), cache $CACHE_DIR, max 20G"
