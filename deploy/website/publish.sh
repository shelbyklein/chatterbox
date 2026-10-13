#!/usr/bin/env bash
# Copy website/ to the Beelink. Caddy serves the folder directly, so the change is live at once.
set -euo pipefail
cd "$(dirname "$0")/../.."
rsync -a --delete --exclude README.md --exclude '.*' website/ beelink:/srv/projects/chatterbox-site/site/
echo "Published to https://chatterbox.shelbyklein.com"
