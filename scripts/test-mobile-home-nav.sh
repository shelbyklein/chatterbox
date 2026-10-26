#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
# Edge swipes between Golem and Chats, Back still working, and the list/cards toggle, against
# an isolated mock companion server (tests/mobile-home-nav/server.py).
cd "$(dirname "$0")/.."
case "${1:-iphone}" in
  iphone) device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro ;;
  ipad) device_type=com.apple.CoreSimulator.SimDeviceType.iPad-mini-A17-Pro ;;
  # The foldable: starts closed; tests unfold it with simctl (CHATTERBOX_TEST_FOLDABLE).
  duo) device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-Duo ;;
  *) echo 'Usage: scripts/test-mobile-home-nav.sh [iphone|ipad|duo]' >&2; exit 2 ;;
esac
root=$(pwd)
# The newest iOS runtime that runs this device (27.1 runs only the iPhone Duo).
# MOBILE_TEST_RUNTIME can pin a supported installed runtime for a reproducible regression.
runtime=${MOBILE_TEST_RUNTIME:-$(xcrun simctl list runtimes -j | /usr/bin/python3 -c 'import json,sys; d=sys.argv[1]; r=[x for x in json.load(sys.stdin)["runtimes"] if x["platform"]=="iOS" and x["isAvailable"] and any(t["identifier"]==d for t in x.get("supportedDeviceTypes",[]))]; print(sorted(r,key=lambda x:[int(p) for p in x["version"].split(".")])[-1]["identifier"])' "$device_type")}
mkdir -p build; artifacts=$(mktemp -d "$root/build/mobile-home-nav.XXXXXX")
simulator=''
status=0
server_pid=''
cleanup() {
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; fi
  if [[ -n "$simulator" ]]; then
    xcrun simctl shutdown "$simulator" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator" >/dev/null 2>&1 || true
  fi
  echo "Mobile home navigation artifacts: $artifacts"
}
trap cleanup EXIT
export CHATTERBOX_TEST_OUTPUT="$artifacts"
/usr/bin/python3 tests/mobile-home-nav/server.py > "$artifacts/server.log" 2>&1 &
server_pid=$!
sleep 0.3
# A busy test port is an error; never fall back to the live companion server.
kill -0 "$server_pid"
/usr/bin/python3 - "$root" "$artifacts" <<'PY'
from pathlib import Path
import plistlib,sys
root=Path(sys.argv[1]); out=Path(sys.argv[2])
y='''name: MobileHomeNavRegression
options:
  deploymentTarget:
    iOS: '17.0'
packages:
  RoyalVNC:
    url: https://github.com/royalapplications/royalvnc
    revision: 92d4427c73817d8f849bb289ff190aa4b40c44ea
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
for source in ['ChatterboxMobile','ChatterboxMobile/ChatterboxMobileApp.swift','Core/ChatterboxMobile','Shared','Chatterbox/Views/MarkdownText.swift','Chatterbox/Views/ReaderStyle.swift','Chatterbox/Views/PathLinks.swift']:
    y+='      - path: '+str(root/source)+'\n'
    if source=='ChatterboxMobile': y+='        excludes: [Info.plist, "*.swift"]\n'
y+='''    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.shelbyklein.Chatterbox.HomeNavRegression
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_NSLocalNetworkUsageDescription: Isolated test server
        TARGETED_DEVICE_FAMILY: '1,2'
        INFOPLIST_FILE: Regression-Info.plist
    dependencies:
      - package: RoyalVNC
        product: RoyalVNCKit
        embed: true
  HomeNavTests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: '''+str(root/'tests/mobile-home-nav/HomeNavTests.swift')+'''
    dependencies:
      - target: Regression
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.shelbyklein.Chatterbox.HomeNavRegression.tests
        GENERATE_INFOPLIST_FILE: YES
'''
(out/'project.yml').write_text(y)
with (out/'Regression-Info.plist').open('wb') as f:
    info={'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True},'UILaunchScreen':{}}
    real=plistlib.load((root/'ChatterboxMobile/Info.plist').open('rb'))
    for key in ('UISupportedInterfaceOrientations','UISupportedInterfaceOrientations~ipad'):
        info[key]=real[key]
    plistlib.dump(info,f)
PY
xcodegen generate --spec "$artifacts/project.yml"
simulator=$(xcrun simctl create 'Chatterbox home nav regression' "$device_type" "$runtime")
status=0
xcrun simctl boot "$simulator"
xcrun simctl bootstatus "$simulator" -b
printf '%s' "$simulator" > "$artifacts/simulator"
xcrun simctl ui "$simulator" appearance dark
# Comma-separated identifiers allow focused phone/tablet runs. Always keep a filter
# so macOS Bash 3's nounset handling cannot reject an empty array.
IFS=',' read -r -a test_ids <<< "${MOBILE_TEST_ONLY:-HomeNavTests/HomeNavTests}"
test_filter=()
for test_id in "${test_ids[@]}"; do test_filter+=("-only-testing:$test_id"); done
xcodebuild -project "$artifacts/MobileHomeNavRegression.xcodeproj" -scheme Regression \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator" \
  -derivedDataPath "$PWD/build/DerivedData-MobileTests" -resultBundlePath "$artifacts/results.xcresult" "${test_filter[@]}" test || status=$?
xcrun xcresulttool export attachments --path "$artifacts/results.xcresult" --output-path "$artifacts/screenshots"
exit "${status:-0}"
