import Foundation

// Checks TranscriptPaging.page (the newest rows, worked out from the end) against grouping
// the whole history, over saved chats (read-only), every setting and several page sizes.
// Usage: scripts/test-transcript-paging.sh [conversations dir]
@MainActor func run() -> Int32 {
    let folder = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
        : NSHomeDirectory() + "/Library/Application Support/Chatterbox/Conversations"
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".json") }
    var checks = 0, failures = 0, chats = 0
    var fullTime = 0.0, pageTime = 0.0
    for file in files {
        guard let data = FileManager.default.contents(atPath: folder + "/" + file),
              let record = try? decoder.decode(ConversationRecord.self, from: data) else { continue }
        chats += 1
        let session = ChatSession(record: record)
        let items = record.items
        let allAgents = session.agentsByItem
        for showThinking in [true, false] {
            for groupSteps in [true, false] {
                let paging = TranscriptPaging(showThinking: showThinking, groupSteps: groupSteps, isRunning: false)
                var t = Date()
                let full = paging.rows(items)
                fullTime += Date().timeIntervalSince(t)
                for limit in [1, 12, 40, 80, 120, 10_000] {
                    t = Date()
                    let page = paging.page(items, limit: limit)
                    pageTime += Date().timeIntervalSince(t)
                    checks += 1
                    let expected = Array(full.suffix(limit))
                    let earlier = paging.rows(Array(items[..<page.start]))
                    let agents = session.agents(forItemsFrom: page.start)
                    var problems: [String] = []
                    if page.rows != expected { problems.append("rows differ (\(page.rows.count) vs \(expected.count))") }
                    if page.hasEarlier != (full.count > limit) { problems.append("hasEarlier \(page.hasEarlier) vs \(full.count > limit)") }
                    if !page.hasEarlier && page.rows.count != full.count { problems.append("short page \(page.rows.count) of \(full.count)") }
                    if page.hasEarlier && earlier.count + page.rows.count != full.count { problems.append("earlier \(earlier.count) + page \(page.rows.count) != \(full.count)") }
                    for case .item(let item) in page.rows where item.kind == .user {
                        if agents[item.id] != allAgents[item.id] { problems.append("agent for \(item.id)"); break }
                    }
                    if !problems.isEmpty {
                        failures += 1
                        if failures <= 10 { print("FAIL \(file) thinking=\(showThinking) group=\(groupSteps) limit=\(limit): \(problems.joined(separator: "; "))") }
                    }
                }
            }
        }
    }
    print("\(chats) chats, \(checks) checks, \(failures) failures")
    print(String(format: "time: whole-history grouping %.1f ms total, paged %.1f ms total (6 page sizes)", fullTime * 1000, pageTime * 1000))
    print(failures == 0 && checks > 0 ? "PASS" : "FAIL")
    return failures == 0 && checks > 0 ? 0 : 1
}
exit(MainActor.assumeIsolated { run() })
