# Numeric Tailscale ATS fix

The installed iOS app declares NSAllowsLocalNetworking but no IP-range exceptions. Shelby reports ATS error -1022 on LTE to 100.95.61.124:47321. A read-only unauthenticated Mac request returns 401, confirming the listener is reachable here. Apple documents that iOS 17+ numeric IP HTTP needs explicit NSExceptionDomains entries.

Add insecure-HTTP exceptions only for the private IPv4/Tailscale and local IPv6 ranges the companion accepts. Keep NSAllowsLocalNetworking for Bonjour; keep pairing tokens, fixed companion port, server peer restrictions and normal public ATS intact. Do not enable NSAllowsArbitraryLoads. No server changes, Mac installs/restarts, pairing resets, push or GitHub mutations.

Tracker local:3D90B3C3-33A5-4904-89EC-BB1BAF094A4D; ATS-1 config/native numeric URLSession verification, ATS-2 signed builds/mobile installs. Direct request confirms scope and installation now. Linear GPT-6.1-Sol / medium, same verified session; small shared config change. Readiness R1/R2/R4-R13 pass; R3 n/a (same request/response flow and UI; only transport-policy exception). No blocking questions.

Success: old installed-equivalent ATS produces -1022 in iOS URLSession to the actual numeric Mac address; corrected ATS returns 401 unauthenticated and still blocks public HTTP. Inspect the compiled signed plist, not just YAML. Install on available physical iPhone/iPad and attempt launch/native numeric probe; report locked/offline devices precisely. Simulator or on-Wi-Fi success cannot prove cellular underlay success.

Verification: a DEBUG-only read-only transport probe in the actual mobile app, driven solely by a launch environment variable, emits status/error results to its own sandbox without pairing or tokens. Run old/new policy on a disposable simulator at the real numeric address. Then use the same probe on physical devices if unlocked/reachable. Inspect source/built plist parity. Rollback config and reinstall prior signed app; no data migration, all pairing/drafts preserved.

Reference: https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking
