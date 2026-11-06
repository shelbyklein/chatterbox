#!/bin/bash
# Build once and keep the products locked until installation completes.
set -e
cd "$(dirname "$0")/.."
source scripts/lib/build-lock.sh
source scripts/lib/mac-install.sh
mac_install() {
  mac_build
  mac_install_bundle "$@"
}
with_derived_data_lock "$MAC_DERIVED_DATA" mac_install "$@"
