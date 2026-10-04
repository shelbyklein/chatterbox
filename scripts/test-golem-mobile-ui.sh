#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
kind=${1:-iphone}
case "$kind" in
 iphone) device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro ;;
 ipad) device_type=com.apple.CoreSimulator.SimDeviceType.iPad-mini-A17-Pro ;;
 *) exit 2 ;;
esac
artifacts=$(mktemp -d "$PWD/build/golem-mobile-ui.XXXXXX")
python3 tests/golem-integration/mobile-server.py > "$artifacts/server.log" 2>&1 &
server_pid=$!
sleep 0.3
kill -0 "$server_pid"
simulator=$(xcrun simctl create "Golem separation $kind" "$device_type" com.apple.CoreSimulator.SimRuntime.iOS-26-2)
trap 'kill "$server_pid" 2>/dev/null || true; xcrun simctl shutdown "$simulator" >/dev/null 2>&1 || true; xcrun simctl delete "$simulator" >/dev/null 2>&1 || true; echo "Mobile UI artifacts: $artifacts"' EXIT
xcrun simctl boot "$simulator"
xcrun simctl bootstatus "$simulator" -b
xcrun simctl ui "$simulator" appearance dark
for product in Chatterbox; do
 xcodebuild -project Chatterbox.xcodeproj -scheme "${product}MobileAcceptance" -configuration Debug \
 -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "${GOLEM_MOBILE_DERIVED_DATA:-$artifacts/build}" \
 -resultBundlePath "$artifacts/$product.xcresult" CODE_SIGNING_ALLOWED=NO test > "$artifacts/$product.log" 2>&1
 xcrun xcresulttool export attachments --path "$artifacts/$product.xcresult" --output-path "$artifacts/$product-screenshots"
done

"${GOLEM_REPO:-../Golem}/scripts/test-mobile-ui.sh" "$kind"
