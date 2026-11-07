#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
artifacts=$(mktemp -d "$PWD/build/widget-test.XXXXXX")
trap 'echo "Widget artifacts: $artifacts"' EXIT
/usr/bin/python3 - "$PWD" "$artifacts" <<'PY'
from pathlib import Path
import os,sys
root,out=map(Path,sys.argv[1:])
widget=root/'Core/ChatterboxWidget/ChatterboxWidget.swift'
sync=(root/'Core/ChatterboxMobile/MobileWidgetSync.swift').read_text()
sync=sync.replace('WidgetSnapshot.load()', 'WidgetSnapshot.load(from: Harness.file)')
sync=sync.replace('.save()', '.save(to: Harness.file)')
sync=sync.replace('WidgetCenter.shared.reloadAllTimelines()', 'Harness.reloads += 1')
(out/'Sync.swift').write_text(sync)
source=widget.read_text().replace('@main\n','',1)
source=source.replace('@Environment(\\.widgetFamily) private var family', 'var family: WidgetFamily = .systemMedium')
(out/'Widget.swift').write_text(source)
(out/'project.yml').write_text(f'''name: WidgetRegression
options:
  deploymentTarget:
    iOS: '17.0'
settings:
  base:
    SWIFT_VERSION: '5.0'
    CODE_SIGNING_ALLOWED: NO
targets:
  WidgetPreview:
    type: application
    platform: iOS
    sources:
      - path: {root}/tests/widget/Preview.swift
      - path: Widget.swift
      - path: {root}/Core/Shared/WidgetSnapshot.swift
      - path: {root}/Core/Shared/Flavor.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.shelbyklein.Chatterbox.WidgetRegression
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        TARGETED_DEVICE_FAMILY: '1'
  WidgetTests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: {root}/tests/widget/WidgetTests.swift
    dependencies:
      - target: WidgetPreview
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.shelbyklein.Chatterbox.WidgetRegression.tests
        GENERATE_INFOPLIST_FILE: YES
''')
PY
swiftc -parse-as-library Core/Shared/Flavor.swift Core/Shared/CompanionAPI.swift Core/Shared/WidgetSnapshot.swift \
  "$artifacts/Sync.swift" tests/widget/ModelChecks.swift -o "$artifacts/model-checks"
"$artifacts/model-checks" "$artifacts/snapshot.json"
if [[ "${WIDGET_MODEL_ONLY:-0}" == 1 ]]; then exit 0; fi
xcodegen generate --spec "$artifacts/project.yml"
xcodebuild -project "$artifacts/WidgetRegression.xcodeproj" -scheme WidgetPreview \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$PWD/build/DerivedData-MobileTests" -testProductsPath "$artifacts/tests.xctestproducts" \
  ARCHS="$(uname -m)" build-for-testing > "$artifacts/build.log" 2>&1 || { tail -70 "$artifacts/build.log"; exit 1; }
simulator=$(test_simulator iphone com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-2)
status=0
filter=()
if [[ -n "${WIDGET_TEST_ONLY:-}" ]]; then
  filter+=("-only-testing:WidgetTests/WidgetTests/$WIDGET_TEST_ONLY")
else
  filter+=('-skip-testing:WidgetTests/WidgetTests/testBefore')
fi
xcodebuild -testProductsPath "$artifacts/tests.xctestproducts" -destination "platform=iOS Simulator,id=$simulator" \
  -resultBundlePath "$artifacts/results.xcresult" "${filter[@]}" test-without-building || status=$?
xcrun xcresulttool export attachments --path "$artifacts/results.xcresult" --output-path "$artifacts/screenshots"
exit "$status"
