#!/bin/bash
# Checks that the build inputs agree before shipping (ship.sh runs it):
#  - Chatterbox.xcodeproj matches project.yml. A file added to Core (often by another chat)
#    doesn't build in Xcode until the project is regenerated; this regenerates it and stops
#    so the change gets reviewed and committed.
#  - the service's hand-written source lists name only real files, once each.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/source-list.sh
xcodegen generate --quiet
# xcodegen writes the two "Embed Dependencies" phases (the host app, the command-line tools)
# in either order. Same lines in another order isn't a change: keep the committed file.
pbx=Chatterbox.xcodeproj/project.pbxproj
if ! git diff --quiet -- "$pbx" && cmp -s <(git show HEAD:"$pbx" | sort) <(sort "$pbx"); then
  git checkout -- "$pbx"
fi
if ! git diff --quiet -- Chatterbox.xcodeproj; then
  echo "The Xcode project was out of date with project.yml; it has been regenerated:" >&2
  git diff --stat -- Chatterbox.xcodeproj >&2
  echo "Review it, stage it (git add Chatterbox.xcodeproj) and ship again." >&2
  exit 1
fi
# Chatterbox Dev (plans/dev-environment.md): the Dev configuration exists, and every target that
# names its Swift files one by one also compiles Flavor.swift, where the identities live.
/usr/bin/python3 -I - project.yml <<'PY' || exit 1
import re, sys
text = open(sys.argv[1]).read()
problems = []
if not re.search(r'^configs:\n(  \w+: \w+\n)*  Dev: debug$', text, re.M):
    problems.append("project.yml has no Dev configuration (configs: Dev: debug)")
targets = text.split('\ntargets:\n', 1)[1].split('\nschemes:', 1)[0]
for block in re.split(r'\n(?=  [A-Za-z]+:\n)', targets):
    name = block.strip().split(':', 1)[0]
    paths = re.findall(r'^    - path: (\S+)$', block, re.M)
    listed = [p for p in paths if p.startswith('Core/') and p.endswith('.swift')]
    if listed and 'Core/Shared' not in paths and 'Core/Shared/Flavor.swift' not in paths:
        problems.append(f"{name} lists its sources but not Core/Shared/Flavor.swift")
if problems:
    print("\n".join(problems), file=sys.stderr); sys.exit(1)
PY
manifest=$(mktemp /tmp/chatterbox-sources.XXXXXX)
trap 'rm -f "$manifest"' EXIT
./scripts/runtime-sources.sh > "$manifest"
check_source_list "$manifest"
echo "Sources check out."
