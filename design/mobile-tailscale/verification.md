# ATS verification — 2026-10-02

Root cause: the shipped Info.plist had NSAllowsLocalNetworking only. iOS 17+ requires explicit numeric IP/CIDR exceptions. The source and signed device build now list only loopback, RFC1918, IPv4 link-local, Tailscale CGNAT, IPv6 loopback/link-local/ULA ranges, matching the companion's accepted peer networks. No arbitrary-load exception, pairing changes, server edits or Mac restarts.

`codesign --verify --deep --strict` passed for the iOS device app. Inspected its generated Info.plist and the installed simulator's runtime Bundle.main ATS dictionary; the YAML, source plist, signed build and simulator runtime agree.

`./scripts/test-mobile-ats.sh 100.95.61.124 10.0.0.156` passed in a fresh disposable iOS 26.2 simulator using the actual Chatterbox mobile executable and URLSession:

| Numeric endpoint | Original shipped-equivalent policy | Corrected policy |
|---|---|---|
| Mac Tailscale 100.95.61.124:47321/v1/chats | ATS -1022 | HTTP 401 |
| Mac LAN 10.0.0.156:47321/v1/chats | HTTP 401 | HTTP 401 |
| Public 1.1.1.1:47321/v1/chats | ATS -1022 | ATS -1022 |

401 is expected: the diagnostic sends no pairing token, performs only read-only GETs, and never pairs. This proves numeric Tailscale HTTP passes ATS while authentication is still required. The public control stays blocked before connecting. Evidence: [before](probe-before-regression.json), [after](probe-after-regression.json), [signed device ATS](ats-signed-device-build.json). The opt-in diagnostic is DEBUG-only and inactive during normal launches.

Physical installation: corrected build successfully installed on iPhone 17 Pro and iPad mini; both verified in their installed-app lists. Launch attempts were rejected by iOS because both devices were locked. Thus no physical-device runtime ATS extraction or cellular connection is claimed. Unlocking and opening Chatterbox is still needed for end-to-end LTE acceptance. The signed installed payload was inspected before transfer.

Mac app PID 66959 and durable host PID 43150 remained unchanged. Neither installed Mac bundle nor its processes were modified. No push performed.
