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
