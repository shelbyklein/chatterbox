#!/bin/bash
# Builds the iPhone app and installs it straight onto a paired phone, over Wi-Fi once it has
# been paired by cable (no TestFlight wait). Signing is automatic: the App Store Connect API key
# lets Xcode register the phone and make the development profile.
#
#   scripts/install-phone.sh                 the first paired phone with Developer Mode on
#   scripts/install-phone.sh "Shelby's Duo"  a phone by name (or its UDID)
#
# One-time on the phone: trust this Mac, then Settings → Privacy & Security → Developer Mode.
set -euo pipefail
cd "$(dirname "$0")/.."
config="$HOME/.appstoreconnect/config"
auth=(-allowProvisioningUpdates)
if [[ -f "$config" ]]; then
  # shellcheck disable=SC1090
  source "$config"
  auth+=(-authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID")
fi
list=$(mktemp /tmp/chatterbox-devices.XXXXXX); trap 'rm -f "$list"' EXIT
xcrun devicectl list devices --json-output "$list" >/dev/null
device=$(/usr/bin/python3 - "$list" "${1:-}" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
want = sys.argv[2]
for d in devices:
    p, h, c = d.get("deviceProperties", {}), d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if h.get("reality") != "physical" or h.get("platform") != "iOS" or c.get("pairingState") != "paired": continue
    if want and want not in (p.get("name"), h.get("udid")): continue
    if p.get("developerModeStatus") != "enabled":
        print("ERR " + p.get("name", "?") + " has Developer Mode off (Settings → Privacy & Security → Developer Mode)"); sys.exit()
    print(h["udid"] + " " + p.get("name", "")); sys.exit()
print("ERR no paired phone" + (" named " + want if want else ""))
PY
)
[[ "$device" == ERR* ]] && { echo "${device#ERR }" >&2; exit 1; }
udid=${device%% *}
# A phone new to the developer account is registered first, so its profile can include it.
[[ -f "$config" ]] && /usr/bin/python3 -I scripts/register-device.py "$udid" "${device#* }"
echo "Building for ${device#* }…"
# Release: Debug runs the Screen Sharing decoding and sign-in maths about 25 times slower.
xcodebuild -project Chatterbox.xcodeproj -scheme ChatterboxMobile -configuration Release \
  -destination "id=$udid" -derivedDataPath build/DerivedDataMobile "${auth[@]}" \
  APNS_ENVIRONMENT=development -quiet build   # Development-signed, so its push tokens are the sandbox's.
app=$(ls -d build/DerivedDataMobile/Build/Products/Release-iphoneos/*.app | head -1)
source scripts/lib/check-embedded.sh
check_embedded "$app"
xcrun devicectl device install app --device "$udid" "$app" | tail -3
bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
xcrun devicectl device process launch --device "$udid" "$bundle" >/dev/null 2>&1 && echo "Installed and opened on ${device#* }." || echo "Installed on ${device#* } (open it there)."
