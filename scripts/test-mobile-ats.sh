#!/bin/bash
# Read-only requests to a running companion, in a disposable iOS simulator.
# Usage: scripts/test-mobile-ats.sh 100.x.y.z [LAN-IP]
set -euo pipefail
cd "$(dirname "$0")/.."
probe_host=${1:?Pass the Mac numeric Tailscale IPv4 address}
probe_lan=${2:-}
artifacts=$(mktemp -d /tmp/chatterbox-ats.XXXXXX)
simulator=''
cleanup() {
  if [[ -n "$simulator" ]]; then
    xcrun simctl shutdown "$simulator" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator" >/dev/null 2>&1 || true
  fi
  echo "Numeric ATS artifacts: $artifacts"
}
trap cleanup EXIT
xcodebuild -project Chatterbox.xcodeproj -scheme ChatterboxMobile -sdk iphonesimulator \
  -configuration Debug -derivedDataPath "$artifacts/build" CODE_SIGNING_ALLOWED=NO build > "$artifacts/build.log" 2>&1
app="$artifacts/build/Build/Products/Debug-iphonesimulator/Chatterbox.app"
cp -R "$app" "$artifacts/before.app"
python3 - "$artifacts/before.app/Info.plist" <<'PY'
import plistlib,sys
path=sys.argv[1];p=plistlib.load(open(path,'rb'))
p['NSAppTransportSecurity']={'NSAllowsLocalNetworking':True}
plistlib.dump(p,open(path,'wb'))
PY
simulator=$(xcrun simctl create 'Chatterbox numeric ATS test' com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-2)
xcrun simctl boot "$simulator"
xcrun simctl bootstatus "$simulator" -b > "$artifacts/boot.log"
for policy in before after; do
  if [[ "$policy" == before ]]; then candidate="$artifacts/before.app"; else candidate="$app"; fi
  xcrun simctl terminate "$simulator" com.shelbyklein.Chatterbox.mobile >/dev/null 2>&1 || true
  xcrun simctl install "$simulator" "$candidate"
  data_dir=$(xcrun simctl get_app_container "$simulator" com.shelbyklein.Chatterbox.mobile data)
  rm -f "$data_dir/Documents/companion-transport-probe.json"
  SIMCTL_CHILD_CHATTERBOX_TRANSPORT_PROBE="$probe_host" SIMCTL_CHILD_CHATTERBOX_TRANSPORT_PROBE_LAN="$probe_lan" \
    xcrun simctl launch "$simulator" com.shelbyklein.Chatterbox.mobile
  python3 - "$data_dir/Documents/companion-transport-probe.json" "$artifacts/$policy.json" "$policy" "$probe_host" <<'PY'
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
