# TestFlight

The iPhone app installs and updates from the TestFlight app, so no cable or Xcode is needed.
`scripts/testflight.sh` archives the Release build and uploads it; each upload gets a new build
number (the date and time). Release builds use Apple's production push service, and the Mac
already sends to the right one for each device.

## One-time setup (in a browser, as the account holder)

1. **Create the app record.** App Store Connect → Apps → + → New App:
   - Platform: iOS
   - Name: anything not already taken on the App Store, e.g. "Chatterbox Companion"
     (testers see the app's own name, Chatterbox, on the Home Screen)
   - Bundle ID: `com.shelbyklein.Chatterbox.mobile`
   - SKU: `chatterbox-mobile`
2. **Sign in to Xcode** (Xcode → Settings → Accounts) with the account holder's Apple ID. The
   script then signs and uploads with that sign-in, and steps 3 and 4 can be skipped.
3. **Or make an API key** (for uploading without the Xcode sign-in). App Store Connect → Users and Access → Integrations → App Store Connect
   API → Team Keys → + . Role: App Manager. Download the `.p8` (it can only be downloaded once)
   and note its Key ID and the Issuer ID shown above the list.
4. **Put the key on the Mac:**

       mkdir -p ~/.appstoreconnect/private_keys
       mv ~/Downloads/AuthKey_<KEY_ID>.p8 ~/.appstoreconnect/private_keys/
       chmod 600 ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
       printf 'KEY_ID=%s\nISSUER_ID=%s\n' <KEY_ID> <ISSUER_ID> > ~/.appstoreconnect/config

5. **Install TestFlight** on the iPhone and iPad from the App Store.

The app record is now **Chatterbox Companion**, Apple ID **6821003584**, with bundle ID
`com.shelbyklein.Chatterbox.mobile` and SKU `chatterbox-mobile`. It was created through
Xcode's first-upload flow on October 9, 2026; don't create another record.

## Each release

    ./scripts/testflight.sh

After Apple processes the build (usually 5–15 minutes), it shows in App Store Connect →
TestFlight. Add yourself once as an internal tester there (Internal Testing → +), and every
later build arrives in the TestFlight app automatically. Internal builds expire after 90 days.

## First upload status — October 9, 2026

Build **202610090952**, version **1.0**, was accepted by App Store Connect; `xcodebuild`
reported **EXPORT SUCCEEDED** and **Uploaded package is processing**. The app and widget
both use `CURRENT_PROJECT_VERSION`, so subsequent uploads get the script's new build number.
The archive is in `build/TestFlight/Chatterbox-202610090952.xcarchive` (replaced on the next release).

Still to verify in App Store Connect: processing completion, an internal testing group,
the account holder added as a tester, and the build assigned to that group. A browser sign-in
is required to complete those steps; an accepted upload alone doesn't make the app available
on the phone.
