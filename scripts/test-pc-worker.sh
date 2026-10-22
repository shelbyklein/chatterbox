#!/bin/bash
# Chats on Shelby-PC without the PC: a stand-in ssh (tests/pc-worker/ssh) runs the real
# worker on this Mac with the fake provider, so launch, folders, open models and stop are
# checked end to end. Needs node and the built ChatterboxHost.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/source-list.sh
task_dir=$(mktemp -d /tmp/pc-worker-test.XXXXXX)
trap 'echo "PC worker test artifacts: $task_dir"' EXIT
export CHATTERBOX_DATA_DIR="$task_dir/data" CHATTERBOX_HOST_DIR="$task_dir/host"
export CHATTERBOX_HOST_BINARY="$PWD/build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/Helpers/ChatterboxHost.app/Contents/MacOS/ChatterboxHost"
export CHATTERBOX_HOST_NOTIFY=0 CHATTERBOX_HOST_IDLE_SECONDS=1 CHATTERBOX_HOST_DETACHED_IDLE_SECONDS=1
export FAKE_PROVIDER="$PWD/tests/golem-integration/fake-provider.py"
export FAKE_PROVIDER_LAUNCHES="$task_dir/launches.jsonl"
export PC_TEST_DIR="$task_dir" PC_WORKER="$PWD/deploy/pc-worker/chatterbox-worker.js"
export CHATTERBOX_SSH_BINARY="$PWD/tests/pc-worker/ssh" CHATTERBOX_PC_TUNNEL_PORT=47399
mkdir -p "$CHATTERBOX_DATA_DIR" "$task_dir/bin"
for name in claude codex; do
  printf '#!/bin/bash\nexec python3 "%s" "$@"\n' "$FAKE_PROVIDER" > "$task_dir/bin/$name"
  chmod +x "$task_dir/bin/$name"
done
./scripts/runtime-sources.sh > "$task_dir/sources"
printf '%s\n' ChatterboxDaemon/DaemonContext.swift >> "$task_dir/sources"
cp tests/pc-worker/main.swift "$task_dir/main.swift"
check_source_list "$task_dir/sources"
swiftc -D CHATTERBOX_HEADLESS -whole-module-optimization -Onone \
  -o "$task_dir/core" @"$task_dir/sources" "$task_dir/main.swift"
"$task_dir/core"
