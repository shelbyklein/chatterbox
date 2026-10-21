# Session image recovery

Run `scripts/test-mobile-images.sh iphone` or `scripts/test-mobile-images.sh ipad`.
The real mobile app opens a long session from Projects against an isolated localhost
companion fixture. No production service, pairing or user images are used. Builds reuse
`build/DerivedData-MobileTests`; fixture/simulator cleanup runs even on failure.

Four UI checks cover an HTTP 503 followed by automatic success, cache reuse, an offscreen
older image staying unfetched, the three-attempt limit for persistent failure, automatic
recovery on reentry, manual retry, and leaving during a slow download then returning.
The fixture exposes request counts so a screenshot alone cannot pass recovery checks.
Screenshots capture actual loaded pixels and the persistent-failure fallback.

`MOBILE_IMAGES_ONLY=<method name>` selects one check. Logs, counts, xcresult and screenshots
are retained under `build/mobile-images.*`. The unmodified loader fails the first check
because it issues only one request after the fixture's initial failure.

On iOS 18+, downloads follow actual scroll visibility rather than lazy row creation,
using Apple's [onScrollVisibilityChange](https://developer.apple.com/documentation/swiftui/view/onscrollvisibilitychange(threshold:_:))
with a 1% threshold. iOS 17 retains lazy appearance/disappearance as its compatibility
fallback; both paths cancel view tasks and avoid presenting cancellation as an error.
