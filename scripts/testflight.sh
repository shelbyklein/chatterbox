#!/bin/bash
# Archives the iPhone app and uploads it to TestFlight, so it installs from the TestFlight app
# instead of over a cable from Xcode.
#
# One-time setup (see docs/testflight.md):
#   ~/.appstoreconnect/config                 KEY_ID=… and ISSUER_ID=… (an App Store Connect API key)
#   ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
# Signing is automatic: the key lets Xcode make the distribution certificate and profile.
# Each upload gets a new build number (the date and time); the newest archive is kept in
# build/TestFlight, older ones are removed.
set -euo pipefail
cd "$(dirname "$0")/.."
config="$HOME/.appstoreconnect/config"
[[ -f "$config" ]] || { echo "No App Store Connect key yet: see docs/testflight.md" >&2; exit 1; }
# shellcheck disable=SC1090
source "$config"
key="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
[[ -f "$key" ]] || { echo "Missing $key" >&2; exit 1; }
auth=(-allowProvisioningUpdates -authenticationKeyPath "$key" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID")

build=$(date +%Y%m%d%H%M)
out=build/TestFlight
mkdir -p "$out"
find "$out" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
archive="$out/Chatterbox-$build.xcarchive"

echo "Archiving build $build…"
xcodebuild -project Chatterbox.xcodeproj -scheme ChatterboxMobile -configuration Release \
  -destination generic/platform=iOS -derivedDataPath build/DerivedDataMobile \
  -archivePath "$archive" CURRENT_PROJECT_VERSION="$build" "${auth[@]}" -quiet archive

cat > "$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>9F3MKVW9C5</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST

echo "Uploading to App Store Connect…"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$out/ExportOptions.plist" \
  -exportPath "$out/export" "${auth[@]}"
echo "Uploaded build $build. It appears in TestFlight once Apple finishes processing (usually 5–15 minutes)."
