#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/chatterbox-documents.XXXXXX)
export DOC_TEST_DIR="$task_dir"
rg --follow --files Chatterbox ChatterboxRuntime Shared -g '*.swift' -g '!ChatterboxApp.swift' > "$task_dir/files.txt"
swiftc -D DEBUG -whole-module-optimization -Onone -o "$task_dir/test" @"$task_dir/files.txt" tests/mac-documents/main.swift
"$task_dir/test"
echo "Document artifacts: $task_dir"
