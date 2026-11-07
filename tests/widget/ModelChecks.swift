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
        MobileWidgetSync.clear()
        precondition(WidgetSnapshot.load(from: Harness.file).usage == nil)
        precondition(WidgetSnapshot.load(from: Harness.file).macName.isEmpty)
        MobileWidgetSync.refresh()
        precondition(WidgetSnapshot.load(from: Harness.file).usage == nil)
        print("PASS: legacy snapshots, percentages, missing/expired limits, atomic persistence, unchanged snapshots, usage-only reloads, chat refresh retention and pairing cleanup")
    }
}
