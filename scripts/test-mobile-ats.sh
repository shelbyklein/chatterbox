#!/bin/bash
source "$(dirname "$0")/lib/test-hygiene.sh"
# Read-only requests to a running companion, in a disposable iOS simulator.
# Usage: scripts/test-mobile-ats.sh 100.x.y.z [LAN-IP]
set -euo pipefail
cd "$(dirname "$0")/.."
# An explicit check: `${1:?}` ends the script before test-hygiene.sh's cleanup sees a failure,
# and the run would count as passed without running.
if [[ -z "${1:-}" ]]; then echo 'Usage: scripts/test-mobile-ats.sh 100.x.y.z [LAN-IP] (needs the Mac'"'"'s Tailscale IPv4 address; not run)' >&2; exit 2; fi
probe_host=$1
probe_lan=${2:-}
artifacts=$(mktemp -d /tmp/chatterbox-ats.XXXXXX)
cleanup() {
  echo "Numeric ATS artifacts: $artifacts"
}
trap cleanup EXIT
xcodebuild -project Chatterbox.xcodeproj -scheme ChatterboxMobile -sdk iphonesimulator \
  -configuration Debug -derivedDataPath "$PWD/build/DerivedData-MobileTests" CODE_SIGNING_ALLOWED=NO build > "$artifacts/build.log" 2>&1
# This run's own copies: the device is booted after the build slot goes back, and another run's
# build could replace the shared one meanwhile.
cp -R "$PWD/build/DerivedData-MobileTests/Build/Products/Debug-iphonesimulator/Chatterbox.app" "$artifacts/after.app"
app="$artifacts/after.app"
cp -R "$app" "$artifacts/before.app"
/usr/bin/python3 - "$artifacts/before.app/Info.plist" <<'PY'
import plistlib,sys
path=sys.argv[1];p=plistlib.load(open(path,'rb'))
p['NSAppTransportSecurity']={'NSAllowsLocalNetworking':True}
plistlib.dump(p,open(path,'wb'))
PY
# A test device of this run's own (test-hygiene.sh), shut down when the run ends.
simulator=$(test_simulator iphone com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-2)
for policy in before after; do
  if [[ "$policy" == before ]]; then candidate="$artifacts/before.app"; else candidate="$app"; fi
  xcrun simctl terminate "$simulator" com.shelbyklein.Chatterbox.mobile >/dev/null 2>&1 || true
  xcrun simctl install "$simulator" "$candidate"
  data_dir=$(xcrun simctl get_app_container "$simulator" com.shelbyklein.Chatterbox.mobile data)
  rm -f "$data_dir/Documents/companion-transport-probe.json"
  SIMCTL_CHILD_CHATTERBOX_TRANSPORT_PROBE="$probe_host" SIMCTL_CHILD_CHATTERBOX_TRANSPORT_PROBE_LAN="$probe_lan" \
    xcrun simctl launch "$simulator" com.shelbyklein.Chatterbox.mobile
  /usr/bin/python3 - "$data_dir/Documents/companion-transport-probe.json" "$artifacts/$policy.json" "$policy" "$probe_host" <<'PY'
import json,sys,time,shutil
from pathlib import Path
source=Path(sys.argv[1]);deadline=time.monotonic()+30
while not source.exists() and time.monotonic()<deadline:time.sleep(.2)
d=json.loads(source.read_text());rows={r['host']:r for r in d['results']}
if sys.argv[3]=='before':assert rows[sys.argv[4]].get('errorCode')==-1022,d
else:
 assert rows[sys.argv[4]].get('status')==401,d
 assert not d['ats'].get('NSAllowsArbitraryLoads',False),d
assert rows['1.1.1.1'].get('errorCode')==-1022,d
shutil.copyfile(source,sys.argv[2]);print(sys.argv[3],json.dumps(d['results']))
PY
done
