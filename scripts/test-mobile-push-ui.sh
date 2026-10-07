#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-iphone}" in
  iphone) device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro ;;
  ipad) device_type=com.apple.CoreSimulator.SimDeviceType.iPad-mini-A17-Pro ;;
  *) echo 'Usage: scripts/test-mobile-push.sh [iphone|ipad]' >&2; exit 2 ;;
esac
root=$(pwd)
artifacts=$(mktemp -d /tmp/chatterbox-mobile-push.XXXXXX)
simulator=''
server_pid=''
cleanup() {
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; fi
  if [[ -n "$simulator" ]]; then
    xcrun simctl shutdown "$simulator" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator" >/dev/null 2>&1 || true
  fi
  echo "Mobile conversation artifacts: $artifacts"
}
trap cleanup EXIT
export CHATTERBOX_TEST_OUTPUT="$artifacts"
/usr/bin/python3 tests/mobile-push/server.py > "$artifacts/server.log" 2>&1 &
server_pid=$!
sleep 0.3
# A busy test port is an error; never fall back to the live companion server.
kill -0 "$server_pid"
/usr/bin/python3 - "$root" "$artifacts" <<'PY'
from pathlib import Path
import plistlib,sys
root=Path(sys.argv[1]); out=Path(sys.argv[2])
y='''name: MobileConversationRegression
options:
  deploymentTarget:
    iOS: '17.0'
settings:
  base:
    SWIFT_VERSION: '5.0'
    CODE_SIGNING_ALLOWED: NO
targets:
  Regression:
    type: application
    platform: iOS
    sources:
'''
for source in ['ChatterboxMobile','Shared','Chatterbox/Views/MarkdownText.swift','Chatterbox/Views/ReaderStyle.swift','Chatterbox/Views/PathLinks.swift']:
    y+='      - path: '+str(root/source)+'\n'
    if source=='ChatterboxMobile': y+='        excludes: [Info.plist]\n'
y+='''    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.shelbyklein.Chatterbox.ConversationRegression
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_NSLocalNetworkUsageDescription: Isolated test server
        TARGETED_DEVICE_FAMILY: '1,2'
        INFOPLIST_FILE: Regression-Info.plist
  ConversationTests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: '''+str(root/'tests/mobile-push/PushUITests.swift')+'''
    dependencies:
      - target: Regression
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.shelbyklein.Chatterbox.ConversationRegression.tests
        GENERATE_INFOPLIST_FILE: YES
'''
(out/'project.yml').write_text(y)
with (out/'Regression-Info.plist').open('wb') as f:
    plistlib.dump({'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True},'UILaunchScreen':{}},f)
PY
xcodegen generate --spec "$artifacts/project.yml"
simulator=$(xcrun simctl create 'Chatterbox push regression' "$device_type" com.apple.CoreSimulator.SimRuntime.iOS-26-2)
xcrun simctl boot "$simulator"
xcrun simctl bootstatus "$simulator" -b
printf '%s' "$simulator" > "$artifacts/simulator"
xcrun simctl ui "$simulator" appearance dark
xcodebuild -project "$artifacts/MobileConversationRegression.xcodeproj" -scheme Regression \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator" \
  -derivedDataPath "$PWD/build/DerivedData-MobileTests" -resultBundlePath "$artifacts/results.xcresult" test
xcrun xcresulttool export attachments --path "$artifacts/results.xcresult" --output-path "$artifacts/screenshots"
