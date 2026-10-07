#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-iphone}" in
  iphone) device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro ;;
  ipad) device_type=com.apple.CoreSimulator.SimDeviceType.iPad-mini-A17-Pro ;;
  *) echo 'Usage: scripts/test-mobile-composer.sh [iphone|ipad]' >&2; exit 2 ;;
esac
export GOLEM_TEST_PRODUCT="${GOLEM_TEST_PRODUCT:-chatterbox}"
root=$(pwd)
artifacts=${CHATTERBOX_TEST_ARTIFACTS:-$(mktemp -d /tmp/chatterbox-mobile-composer.XXXXXX)}
results="$artifacts/results-$(date +%s).xcresult"
simulator=''
server_pid=''
cleanup() {
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; fi
  if [[ -n "$simulator" ]]; then
    xcrun simctl shutdown "$simulator" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator" >/dev/null 2>&1 || true
  fi
  echo "Mobile composer artifacts: $artifacts"
}
trap cleanup EXIT
swiftc -parse-as-library ChatterboxMobile/MobileComposerDraft.swift tests/mobile-composer/DraftLifecycle.swift -o "$artifacts/draft-lifecycle"
"$artifacts/draft-lifecycle"
export CHATTERBOX_TEST_OUTPUT="$artifacts"
/usr/bin/python3 tests/mobile-composer/server.py > "$artifacts/server.log" 2>&1 &
server_pid=$!
sleep 0.3
# A busy test port is an error; never fall back to the live companion server.
kill -0 "$server_pid"
/usr/bin/python3 - "$root" "$artifacts" <<'PY'
from pathlib import Path
import plistlib,sys,os
root=Path(sys.argv[1]); out=Path(sys.argv[2])
y='''name: MobileComposerRegression
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
for source in (['GolemMobile'] if os.environ.get('GOLEM_TEST_PRODUCT')=='golem' else [])+['ChatterboxMobile','Shared','Chatterbox/Views/MarkdownText.swift','Chatterbox/Views/ReaderStyle.swift','Chatterbox/Views/PathLinks.swift']:
    y+='      - path: '+str(Path(os.environ.get('GOLEM_REPO',str(root.parent/'Golem')))/source if source=='GolemMobile' else root/source)+'\n'
    if source=='GolemMobile': y+='        excludes: [Info.plist]\n'
    if source=='ChatterboxMobile': y+='        excludes: [Info.plist, Assets.xcassets/AppIcon.appiconset]\n'
y+='''    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.shelbyklein.Chatterbox.ComposerRegression
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_NSLocalNetworkUsageDescription: Isolated test server
        TARGETED_DEVICE_FAMILY: '1,2'
        INFOPLIST_FILE: Regression-Info.plist
  ComposerTests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: '''+str(root/'tests/mobile-composer/ComposerTests.swift')+'''
    dependencies:
      - target: Regression
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.shelbyklein.Chatterbox.ComposerRegression.tests
        GENERATE_INFOPLIST_FILE: YES
'''
if os.environ.get('GOLEM_TEST_PRODUCT')=='golem': y=y.replace('GENERATE_INFOPLIST_FILE: YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) GOLEM_APP\n        GENERATE_INFOPLIST_FILE: YES').replace('PRODUCT_BUNDLE_IDENTIFIER: com.shelbyklein.Chatterbox.ComposerRegression.tests','SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) GOLEM_APP\n        PRODUCT_BUNDLE_IDENTIFIER: com.shelbyklein.Chatterbox.ComposerRegression.tests')
(out/'project.yml').write_text(y)
with (out/'Regression-Info.plist').open('wb') as f:
    plistlib.dump({'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True},'UILaunchScreen':{}},f)
PY
xcodegen generate --spec "$artifacts/project.yml"
simulator=$(xcrun simctl create 'Chatterbox refresh regression' "$device_type" com.apple.CoreSimulator.SimRuntime.iOS-26-2)
xcrun simctl boot "$simulator"
xcrun simctl bootstatus "$simulator" -b
xcodebuild -project "$artifacts/MobileComposerRegression.xcodeproj" -scheme Regression \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator" \
  -derivedDataPath "$PWD/build/DerivedData-MobileTests" -resultBundlePath "$results" test "${@:2}"
xcrun xcresulttool export attachments --path "$results" --output-path "$artifacts/screenshots"
