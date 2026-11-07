import Foundation

@MainActor enum Harness {
    static let file = URL(fileURLWithPath: CommandLine.arguments[1])
    static var reloads = 0
}

@MainActor final class MobileSeenReplies {
    static let shared = MobileSeenReplies()
    func newest(in activity: [Companion.TurnCompletion], limit: Int) -> [Companion.TurnCompletion] {
        Array(activity.prefix(limit))
    }
}

@main struct ModelChecks {
    @MainActor static func main() throws {
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = Data(#"{"updatedAt":"2026-11-07T12:00:00Z","macName":"Fixture","waiting":[],"newReplies":[],"working":[]}"#.utf8)
        let old = try decoder.decode(WidgetSnapshot.self, from: legacy)
        precondition(old.usage == nil)
        precondition(old.macName == "Fixture")
        precondition(WidgetSnapshot.Usage.summary([], at: now) == "Not reported")
        let windows: [WidgetSnapshot.Usage.Window] = [
            .init(label: "5-hour", fraction: 0.42, resetsAt: now.addingTimeInterval(60)),
            .init(label: "7-day", fraction: 0.81, resetsAt: nil)
        ]
        precondition(WidgetSnapshot.Usage.summary(windows, at: now) == "5h 42% · 7d 81% used")
        precondition(windows[0].text(at: now.addingTimeInterval(60)) == "5h —")
        precondition(WidgetSnapshot.Usage.Window(label: "5-hour", fraction: nil, resetsAt: nil).text(at: now) == "5h —")
        precondition(WidgetSnapshot.Usage.Window(label: "5-hour", fraction: .nan, resetsAt: nil).text(at: now) == "5h —")
        precondition(WidgetSnapshot.Usage.Window(label: "7-day", fraction: 2, resetsAt: nil).text(at: now) == "7d 100%")
        precondition(WidgetSnapshot.Usage.Window(label: "7-day", fraction: -1, resetsAt: nil).text(at: now) == "7d 0%")
        precondition(windows[0].usedFraction(at: now) == 0.42)
        precondition(windows[0].usedFraction(at: now.addingTimeInterval(60)) == nil)
        let unavailable: [Double?] = [nil, .nan, .infinity, -.infinity]
        for fraction in unavailable {
            precondition(WidgetSnapshot.Usage.Window(label: "5-hour", fraction: fraction, resetsAt: nil).usedFraction(at: now) == nil)
        }
        for (fraction, expected) in [(-1.0, 0.0), (0, 0), (0.75, 0.75), (0.9, 0.9), (1, 1), (2, 1)] {
            precondition(WidgetSnapshot.Usage.Window(label: "7-day", fraction: fraction, resetsAt: nil).usedFraction(at: now) == expected)
        }
        var snapshot = old
        snapshot.usage = .init(syncedAt: now, claude: windows, codex: [])
        precondition(snapshot.save(to: Harness.file))
        precondition(WidgetSnapshot.load(from: Harness.file) == snapshot)
        snapshot.updatedAt = now.addingTimeInterval(90)
        precondition(!snapshot.save(to: Harness.file))
        snapshot.usage?.codex = [.init(label: "5-hour", fraction: 0.12, resetsAt: nil)]
        precondition(snapshot.save(to: Harness.file))
        precondition(WidgetSnapshot.load(from: Harness.file).usage?.codex.first?.fraction == 0.12)
        MobileWidgetSync.clear()
        let usage = Companion.Usage(claude: [.init(label: "5-hour", fraction: 0.42, resetsAt: now.addingTimeInterval(60))],
                                    codex: [.init(label: "7-day", fraction: nil, resetsAt: nil)],
                                    proxyAccounts: [.init(provider: "claude", name: "Private", status: "Available", windows: [], problem: nil)])
        MobileWidgetSync.updateUsage(usage, at: now.addingTimeInterval(0.25))
        MobileWidgetSync.update(.init(revision: 1, groups: []), macName: "Fixture")
        let saved = WidgetSnapshot.load(from: Harness.file)
        precondition(saved.usage?.claude.first?.fraction == 0.42)
        precondition(saved.usage?.claude.first?.resetsAt == now.addingTimeInterval(60))
        precondition(saved.usage?.codex.first?.fraction == nil)
        precondition(saved.usage?.syncedAt == now)
        let reloads = Harness.reloads
        MobileWidgetSync.update(.init(revision: 2, groups: []), macName: "Fixture")
        precondition(Harness.reloads == reloads)
        precondition(WidgetSnapshot.load(from: Harness.file).usage == saved.usage)
        MobileWidgetSync.updateUsage(.init(claude: [], codex: [.init(label: "5-hour", fraction: 0.3, resetsAt: nil)]), at: now.addingTimeInterval(60))
        precondition(Harness.reloads == reloads + 1)
        precondition(WidgetSnapshot.load(from: Harness.file).usage?.codex.first?.fraction == 0.3)
        let oldUsage = try decoder.decode(WidgetSnapshot.Usage.self, from: Data(#"{"syncedAt":"2026-11-07T12:00:00Z","claude":[],"codex":[]}"#.utf8))
        precondition(oldUsage.proxyAccounts == nil && oldUsage.proxyChecked == nil && oldUsage.proxyRefreshing == nil)
        let quotaReset = now.addingTimeInterval(3600)
        let all = Companion.Usage(claude: [], codex: [.init(label: "5-hour", fraction: 0.12, resetsAt: nil)], proxyAccounts: [
            .init(provider: "claude", name: "Personal", status: "Limited", windows: [
                .quota(label: "5-hour window", remainingPercent: 0, resetsAt: quotaReset),
                .quota(label: "7-day window", remainingPercent: 40, resetsAt: nil)]),
            .init(provider: "claude", name: "Work", status: "Available", windows: [
                .quota(label: "5-hour window", remainingPercent: 70, resetsAt: nil),
                .quota(label: "7-day window", remainingPercent: 80, resetsAt: nil),
                .quota(label: "7-day Sonnet", remainingPercent: 90, resetsAt: nil)]),
            .init(provider: "codex", name: "One", status: "Unavailable", windows: [], problem: "Quota lookup unavailable"),
            .init(provider: "codex", name: "Two", status: "Unavailable", windows: []),
            .init(provider: "codex", name: "Three", status: "Available", windows: [.quota(label: "5-hour window", remainingPercent: 65, resetsAt: nil)])
        ], proxyChecked: now)
        precondition(!MobileWidgetSync.proxyCheckPending(all))
        MobileWidgetSync.updateUsage(all, at: now)
        let full = WidgetSnapshot.load(from: Harness.file).usage!
        precondition(full.claude.isEmpty && full.codex.first?.fraction == 0.12, "direct limits stay separate")
        precondition(full.proxyAccounts?.count == 5 && full.proxyAccounts!.flatMap(\.windows).count == 6)
        precondition(full.proxyAccounts![0].windows[0].fraction == 1 && full.proxyAccounts![0].windows[0].resetsAt == quotaReset)
        precondition(abs(full.proxyAccounts![4].windows[0].fraction! - 0.35) < 0.00001, "remaining converted once")
        precondition(full.proxyAccounts![1].windows[2].text(at: now) == "7d Sonnet 10%", "third window retained")
        precondition(full.proxyAccounts![2].status == "Unavailable" && full.proxyAccounts![2].windows.isEmpty)
        precondition(full.proxyChecked == now && full.proxyRefreshing == false)
        precondition(full.proxyAccounts![1].tightest(at: now)?.compactLabel == "5h")
        let pending = Companion.Usage(claude: [], codex: [], proxyAccounts: [])
        precondition(MobileWidgetSync.proxyCheckPending(pending))
        MobileWidgetSync.updateUsage(pending, at: now.addingTimeInterval(30))
        let checking = WidgetSnapshot.load(from: Harness.file).usage!
        precondition(checking.proxyRefreshing == true && checking.proxyChecked == now)
        precondition(checking.proxyAccounts == full.proxyAccounts, "cold server preserves checked readings and age")
        precondition(!MobileWidgetSync.proxyCheckPending(Companion.Usage(claude: [], codex: [], proxyAccounts: [], proxyProblem: "Unavailable")))
        precondition(!MobileWidgetSync.proxyCheckPending(Companion.Usage(claude: [], codex: [], proxyAccounts: [], proxyChecked: now)))
        precondition(!MobileWidgetSync.proxyCheckPending(Companion.Usage(claude: [], codex: [])))
        let malformed = Companion.Usage(claude: [], codex: [], proxyAccounts: [
            .init(provider: "claude", name: "Unknown", status: "Disabled", windows: [
                .init(label: "5-hour", fraction: nil, resetsAt: nil), .init(label: "7-day", fraction: .nan, resetsAt: nil),
                .init(label: "Expired", fraction: 0.5, resetsAt: now), .init(label: "Full", fraction: -1, resetsAt: nil),
                .init(label: "Empty", fraction: 2, resetsAt: nil)])
        ], proxyChecked: now)
        MobileWidgetSync.updateUsage(malformed, at: now.addingTimeInterval(60))
        let malformedSaved = WidgetSnapshot.load(from: Harness.file).usage!.proxyAccounts![0]
        precondition(malformedSaved.status == "Disabled" && malformedSaved.windows.count == 5)
        precondition(malformedSaved.windows[0].fraction == nil && malformedSaved.windows[1].fraction == nil)
        precondition(malformedSaved.windows[2].usedFraction(at: now) == nil)
        precondition(malformedSaved.windows[3].fraction == 1 && malformedSaved.windows[4].fraction == 0)
        MobileWidgetSync.updateUsage(.init(claude: [], codex: []), at: now.addingTimeInterval(90))
        precondition(WidgetSnapshot.load(from: Harness.file).usage?.proxyAccounts == nil, "unconfigured proxy clears old accounts")
        MobileWidgetSync.clear()
        precondition(WidgetSnapshot.load(from: Harness.file).usage == nil)
        print("PASS all-account widget cache: all windows/statuses, remaining-to-used normalization, legacy decode, cold-check retention, timestamps, unknown/expired and cleanup")
        precondition(WidgetSnapshot.load(from: Harness.file).macName.isEmpty)
        MobileWidgetSync.refresh()
        precondition(WidgetSnapshot.load(from: Harness.file).usage == nil)
        print("PASS: legacy snapshots, percentages, missing/expired limits, atomic persistence, unchanged snapshots, usage-only reloads, chat refresh retention and pairing cleanup")
    }
}
