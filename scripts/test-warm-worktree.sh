#!/bin/bash
# scripts/warm-worktree.sh, on a fixture repo: `git worktree add` (through the installed hook)
# clones the main checkout's build folders copy-on-write, leaves app bundles, Logs, TestResults
# and the rest of build/ behind, keeps a worktree's own build folders, never re-warms on a plain
# checkout, and waits for (then skips) a build running in the main checkout.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
fixture=$(mktemp -d /tmp/chatterbox-test-warm-worktree.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
fail() { echo "FAIL $*"; exit 1; }
pass() { echo "PASS $*"; }

main="$fixture/main"
mkdir -p "$main/scripts"
cp scripts/warm-worktree.sh "$main/scripts/"
git -C "$main" init -q -b main
git -C "$main" -c user.name=t -c user.email=t@t add scripts
git -C "$main" -c user.name=t -c user.email=t@t commit -qm fixture
printf 'build/\n' > "$main/.git/info/exclude"

# The main checkout's build state, as Xcode and the scripts leave it.
dd="$main/build/DerivedData"
mkdir -p "$dd/Build/Intermediates.noindex/App.build/Debug/App.build/Objects-normal/arm64" \
  "$dd/Build/Products/Debug/App.app/Contents/MacOS" "$dd/Build/Products/Debug/Helper.app/Contents" \
  "$dd/Build/Intermediates.noindex/ArchiveIntermediates/App/BuildProductsPath/Release" \
  "$dd/SourcePackages/checkouts/Pkg" "$dd/Logs/Build" "$dd/TestResults" "$dd/ModuleCache.noindex" \
  "$main/build/DerivedDataMobile/Build/Products/Release-iphoneos/App.app" "$main/build/runtime" \
  "$main/build/mobile-home-nav.AbC123/DerivedData/Build/Products/Debug/App.app"
object="Build/Intermediates.noindex/App.build/Debug/App.build/Objects-normal/arm64/Main.o"
head -c 4194304 /dev/urandom > "$dd/$object"
printf 'binary' > "$dd/Build/Products/Debug/App.app/Contents/MacOS/App"
printf 'lib' > "$dd/Build/Products/Debug/libKit.a"
printf 'pkg' > "$dd/SourcePackages/checkouts/Pkg/Package.swift"
printf 'log' > "$dd/Logs/Build/x.xcactivitylog"
printf 'result' > "$dd/TestResults/r"
printf 'module' > "$dd/ModuleCache.noindex/Foundation.pcm"
printf 'plist' > "$dd/info.plist"
ln -s ../../InstallationBuildProductsLocation/Applications/App.app \
  "$dd/Build/Intermediates.noindex/ArchiveIntermediates/App/BuildProductsPath/Release/App.app"
printf 'mobile' > "$main/build/DerivedDataMobile/Build/Products/Release-iphoneos/App.app/App"
printf 'daemon' > "$main/build/runtime/chatterboxd"
printf 'log' > "$main/build/some-run.log"

# Physical block of a file's start: clones share it, copies don't (F_LOG2PHYS).
phys() {
  /usr/bin/python3 -I -c '
import fcntl, os, struct, sys
fd = os.open(sys.argv[1], os.O_RDONLY)
print(struct.unpack("=Iqq", fcntl.fcntl(fd, 49, struct.pack("=Iqq", 0, 0, 0)))[2])' "$1"
}

# --- The hook ------------------------------------------------------------------------------
(cd "$main" && scripts/warm-worktree.sh --install-hook) 2>/dev/null
grep -q chatterbox-warm-worktree "$main/.git/hooks/post-checkout" || fail "hook not installed"
pass "hook installed"
(cd "$main" && scripts/warm-worktree.sh --install-hook) 2>/dev/null || fail "reinstalling our hook"
printf '#!/bin/sh\necho theirs\n' > "$fixture/other-hook"
cp "$main/.git/hooks/post-checkout" "$fixture/ours"; cp "$fixture/other-hook" "$main/.git/hooks/post-checkout"
if (cd "$main" && scripts/warm-worktree.sh --install-hook) 2>/dev/null; then fail "replaced someone else's post-checkout hook"; fi
cp "$fixture/ours" "$main/.git/hooks/post-checkout"
pass "an existing hook of someone else's is left alone"

wt="$fixture/wt"
out=$(git -C "$main" worktree add -q -b wt "$wt" 2>&1)
echo "$out" | grep -q "cloned DerivedData DerivedDataMobile runtime" || fail "worktree add didn't warm: $out"
pass "git worktree add warms the new worktree ($(echo "$out" | grep -o 'in [0-9]*s'))"

w="$wt/build/DerivedData"
cmp -s "$dd/$object" "$w/$object" || fail "intermediates not cloned"
[[ "$(phys "$dd/$object")" == "$(phys "$w/$object")" ]] || fail "intermediates copied, not cloned"
[[ "$(stat -f %i "$dd/$object")" != "$(stat -f %i "$w/$object")" ]] || fail "a hard link, not a clone"
pass "intermediates cloned copy-on-write (same blocks, own file)"
echo changed >> "$w/$object"
cmp -s "$dd/$object" "$w/$object" && fail "writing the clone changed the main checkout's file"
pass "writing the clone leaves the main checkout's file alone"

for f in Build/Products/Debug/libKit.a SourcePackages/checkouts/Pkg/Package.swift ModuleCache.noindex/Foundation.pcm info.plist; do
  [[ -f "$w/$f" ]] || fail "missing $f"
done
[[ -f "$wt/build/runtime/chatterboxd" ]] || fail "runtime not cloned"
pass "products, packages, module cache and runtime cloned"

apps=$(find "$wt/build" -name '*.app' | sed "s|$wt/||")
[[ -z "$apps" ]] || fail "app bundles copied: $apps"
[[ ! -e "$w/Logs" && ! -e "$w/TestResults" ]] || fail "Logs or TestResults copied"
[[ ! -e "$wt/build/some-run.log" && ! -e "$wt/build/mobile-home-nav.AbC123" ]] || fail "other build/ contents copied"
[[ -z "$(find "$wt/build" -name '.*.warming')" ]] || fail "a partial clone left behind"
pass "no app bundles, Logs, TestResults, per-run folders or logs copied"

# --- Not again ----------------------------------------------------------------------------
printf 'mine' > "$w/Build/Products/Debug/libKit.a"
out=$(git -C "$wt" checkout -q -b other 2>&1)
[[ -z "$out" && "$(cat "$w/Build/Products/Debug/libKit.a")" == mine ]] || fail "a plain checkout re-warmed: $out"
out=$(cd "$wt" && "$main/scripts/warm-worktree.sh" 2>&1)
echo "$out" | grep -q "keeping the worktree's own build/DerivedData" || fail "didn't keep the worktree's own build: $out"
[[ "$(cat "$w/Build/Products/Debug/libKit.a")" == mine ]] || fail "replaced the worktree's own build"
pass "a plain checkout and a second run keep the worktree's own build"
out=$("$main/scripts/warm-worktree.sh" --force "$wt" 2>&1)
[[ "$(cat "$w/Build/Products/Debug/libKit.a")" == lib ]] || fail "--force didn't replace: $out"
pass "--force replaces it"
out=$(cd "$main" && scripts/warm-worktree.sh 2>&1)
echo "$out" | grep -q "main checkout; nothing to do" || fail "warming the main checkout itself: $out"
pass "the main checkout itself is left alone"

# --- While the main checkout builds ---------------------------------------------------------
locks="$fixture/locks"; mkdir -p "$locks/slot-1"
sleep 600 & builder=$!
printf '%s\n' "$builder" > "$locks/slot-1/pid"; printf '%s\n' "$(cd "$main" && pwd -P)" > "$locks/slot-1/worktree"
wt2="$fixture/wt2"
out=$(CHATTERBOX_BUILD_LOCK_DIR="$locks" CHATTERBOX_WARM_WAIT=2 git -C "$main" worktree add -q -b wt2 "$wt2" 2>&1)
echo "$out" | grep -q "waiting for the build in" || fail "didn't wait for the main checkout's build: $out"
[[ ! -e "$wt2/build" ]] || fail "cloned a build in progress"
[[ -d "$wt2/scripts" ]] || fail "the worktree wasn't made"
pass "waits for a build in the main checkout, and gives up without cloning it"
(sleep 3; kill "$builder" 2>/dev/null) &
out=$(CHATTERBOX_BUILD_LOCK_DIR="$locks" "$main/scripts/warm-worktree.sh" "$wt2" 2>&1)
echo "$out" | grep -q "cloned DerivedData" || fail "didn't clone once the build finished: $out"
pass "clones once the build has finished"

# --- No build state, no fuss ---------------------------------------------------------------
rm -rf "$main/build"
out=$(git -C "$main" worktree add -q -b wt3 "$fixture/wt3" 2>&1)
echo "$out" | grep -q "nothing to clone" || fail "unexpected: $out"
pass "nothing to clone is fine"

echo "warm-worktree: all passed"
