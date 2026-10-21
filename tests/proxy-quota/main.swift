import Foundation

Task { @MainActor in
    let claude = ProxyQuotaStore.windows(["five_hour": ["utilization": 100, "resets_at": "2026-10-05T13:00:00Z"], "seven_day": ["utilization": NSNull()]], provider: "claude")
    precondition(claude[0].remaining == 0 && claude[0].reset != nil)
    precondition(claude[1].remaining == nil)
    let codex = ProxyQuotaStore.windows(["rate_limit": ["primary_window": ["used_percent": 4, "limit_window_seconds": 604800, "reset_after_seconds": 50]], "additional_rate_limits": [["limit_name": "reserve", "rate_limit": ["primary_window": ["used_percent": 0]]]]], provider: "codex", now: Date(timeIntervalSince1970: 100))
    precondition(codex.count == 2 && codex[0].remaining == 96 && codex[0].reset == Date(timeIntervalSince1970: 150))
    precondition(codex[1].remaining == 100)
    precondition(ProxyQuotaStore.windows([:], provider: "codex").isEmpty)
    precondition(ProxyQuotaStore.windows(["five_hour": ["utilization": true]], provider: "claude")[0].remaining == nil)
    // Use provider percentages, not pre-normalized mock API values: the old companion
    // mapping sent 65 rather than 0.65, so the phone displayed 100% for nearly every quota.
    let reset = "2026-10-25T04:00:00Z"
    let percentages: [Double?] = [0, 28, 65, 37, 93, 100, 0.5, nil]
    for provider in ["claude", "codex"] {
        let windows = percentages.flatMap { percent -> [ProxyQuotaWindow] in
            let used: Any = percent.map { 100 - $0 } ?? NSNull()
            let payload: [String: Any] = provider == "claude"
                ? ["five_hour": ["utilization": used, "resets_at": reset]]
                : ["rate_limit": ["primary_window": ["used_percent": used, "reset_at": reset]]]
            return ProxyQuotaStore.windows(payload, provider: provider)
        }
        let payload = Companion.Usage(claude: [.init(label: "5-hour", fraction: 0.35, resetsAt: nil)], codex: [],
                                      proxyAccounts: [.init(provider: provider, name: "Fixture", status: "Available",
                                                            windows: windows.map { .quota(label: $0.title, remainingPercent: $0.remaining, resetsAt: $0.reset) })])
        let data = try! Companion.encoder.encode(payload)
        let phone = try! Companion.decoder.decode(Companion.Usage.self, from: data)
        precondition(phone.claude[0].fraction == 0.35, "direct agent fraction changed")
        let received = phone.proxyAccounts![0].windows
        precondition(received.count == percentages.count)
        for (window, percent) in zip(received, percentages) {
            precondition(window.fraction == percent.map { $0 / 100 }, "proxy percentage isn't a wire fraction")
            precondition(window.resetsAt == ISO8601DateFormatter().date(from: reset), "reset date changed")
            if let fraction = window.fraction, let percent {
                let displayed = Int((min(1, max(0, fraction)) * 100).rounded())
                precondition(displayed == Int(percent.rounded()), "iOS displayed the wrong percentage")
            }
        }
    }
    print("PASS mobile quota serialization: provider percentages → 0–1 wire fractions → correct iOS percentages; unknown/reset/direct limits preserved")
    print("PASS quota parsing: exhausted, unknown, reset dates, additional pools, malformed percentages")
    if CommandLine.arguments.contains("--live") {
        await ProxyQuotaStore.shared.refresh()
        precondition(ProxyQuotaStore.shared.problem == nil)
        precondition(!ProxyQuotaStore.shared.accounts.isEmpty)
        for account in ProxyQuotaStore.shared.accounts {
            print("\(account.provider): \(account.status); \(account.windows.count) windows")
        }
    }
    exit(0)
}
RunLoop.main.run()
