#!/bin/bash
# Sets up Shelby-PC as a Chatterbox worker over SSH (see plans/pc-worker.md): copies
# chatterbox-worker.js and the Ollama launcher to ~/.chatterbox on the PC, creates
# D:\Chatterbox\{workspaces,attachments}, registers the "Chatterbox Ollama" logon task and
# starts Ollama if it isn't running. Safe to run again. `--remove` takes the worker and the
# task off the PC; workspaces and Ollama's models stay.
set -euo pipefail
cd "$(dirname "$0")/.."
host=${PC_SSH_HOST:-desktop}
run() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" "$1"; }
if [[ ${1-} == --remove ]]; then
  run 'powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.chatterbox\install.ps1" -Remove'
  exit
fi
run 'New-Item -ItemType Directory -Force "$env:USERPROFILE\.chatterbox" | Out-Null'
scp -q -B deploy/pc-worker/chatterbox-worker.js deploy/pc-worker/ollama-serve.vbs deploy/pc-worker/install.ps1 "$host:.chatterbox/"
run 'powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.chatterbox\install.ps1"'
run 'node "$env:USERPROFILE\.chatterbox\chatterbox-worker.js" --version'
run '$m = (Invoke-RestMethod http://127.0.0.1:11434/api/tags -TimeoutSec 20).models.name; "Ollama models: " + ($m -join ", ")'
