#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/chatterbox-documents.XXXXXX)
export DOC_TEST_DIR="$task_dir"
find -L Chatterbox ChatterboxRuntime Shared -name '*.swift' ! -name 'ChatterboxApp.swift' > "$task_dir/files.txt"
swiftc -I build/DerivedData/Build/Products/Debug build/DerivedData/Build/Products/Debug/SwiftTerm.o -framework AVKit -framework WebKit -framework PDFKit -D DEBUG -whole-module-optimization -Onone -o "$task_dir/test" @"$task_dir/files.txt" tests/mac-documents/main.swift
"$task_dir/test"
echo "Document artifacts: $task_dir"
