#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-iphone}" in
  iphone) device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro ;;
  ipad) device_type=com.apple.CoreSimulator.SimDeviceType.iPad-mini-A17-Pro ;;
  *) echo 'Usage: scripts/test-mobile-pdf.sh [iphone|ipad]' >&2; exit 2 ;;
esac
root=$(pwd)
artifacts=$(mktemp -d /tmp/chatterbox-mobile-pdf.XXXXXX)
server_pid=''
cleanup() {
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; fi
  echo "Mobile PDF artifacts: $artifacts"
}
trap cleanup EXIT
export CHATTERBOX_TEST_OUTPUT="$artifacts"
# The fixture server, on a free port of this run's own (test-hygiene.sh): runs never collide.
start_test_server "$artifacts/server.log" /usr/bin/python3 tests/mobile-pdf/server.py
server_pid=$test_server_pid
/usr/bin/python3 - "$root" "$artifacts" <<'PY'
from pathlib import Path
import plistlib,sys
root=Path(sys.argv[1]); out=Path(sys.argv[2])
y='''name: MobilePDFRegression
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
for source in ['ChatterboxMobile','ChatterboxMobile/ChatterboxMobileApp.swift','Core/ChatterboxMobile','Shared','Chatterbox/Views/MarkdownText.swift','Chatterbox/Views/ReaderStyle.swift','Chatterbox/Views/PathLinks.swift']:
    y+='      - path: '+str(root/source)+'\n'
    if source=='ChatterboxMobile': y+='        excludes: [Info.plist, "*.swift"]\n'
y+='''    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.shelbyklein.Chatterbox.PDFRegression
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_NSLocalNetworkUsageDescription: Isolated test server
        TARGETED_DEVICE_FAMILY: '1,2'
        INFOPLIST_FILE: Regression-Info.plist
  PDFTests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: '''+str(root/'tests/mobile-pdf/PDFTests.swift')+'''
    dependencies:
      - target: Regression
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.shelbyklein.Chatterbox.PDFRegression.tests
        GENERATE_INFOPLIST_FILE: YES
'''
(out/'project.yml').write_text(y)
with (out/'Regression-Info.plist').open('wb') as f:
    plistlib.dump({'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True},'UILaunchScreen':{}},f)
PY
xcodegen generate --spec "$artifacts/project.yml"
# Built under the build slot into this run's own test products, then run on a device of its
# own under a simulator slot, so the build slot is free while the tests drive the app
# (test-hygiene.sh). The test products are the run's: another run's build can't replace them.
# Only this Mac's architecture: a generic destination would build x86_64 as well.
products="$artifacts/tests.xctestproducts"; rm -rf "$products"
xcodebuild -project "$artifacts/MobilePDFRegression.xcodeproj" -scheme Regression \
  -configuration Debug -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$PWD/build/DerivedData-MobileTests" -testProductsPath "$products" ARCHS="$(uname -m)" build-for-testing
# A test device of this run's own (test-hygiene.sh), shut down when the run ends.
simulator=$(test_simulator "${1:-iphone}" "$device_type" com.apple.CoreSimulator.SimRuntime.iOS-26-2)
printf '%s' "$simulator" > "$artifacts/simulator"
xcrun simctl ui "$simulator" appearance dark
# The test device is reused run to run (test-hygiene.sh), and the app's saved PDFs with it: a
# saved copy is never downloaded, so the download and cancel checks would see nothing. Start clean.
xcrun simctl uninstall "$simulator" com.shelbyklein.Chatterbox.PDFRegression 2>/dev/null || true
xcodebuild -testProductsPath "$products" -destination "platform=iOS Simulator,id=$simulator" \
  -resultBundlePath "$artifacts/results.xcresult" test-without-building
xcrun xcresulttool export attachments --path "$artifacts/results.xcresult" --output-path "$artifacts/screenshots"
