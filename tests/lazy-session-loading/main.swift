import AppKit
import SwiftUI
import ScreenCaptureKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let fixtureID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
let backgroundID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RuntimeFailure(message) }
    print("PASS \(message)")
}
@MainActor func wait(_ label: String, _ predicate: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(20)
    while !predicate() {
        guard Date() < deadline else { throw RuntimeFailure("Timed out: \(label)") }
        try await Task.sleep(for: .milliseconds(30))
    }
    print("PASS \(label)")
}

@MainActor func seed() throws {
    let root = RuntimePaths.data
    let folder = root.appendingPathComponent("Conversations")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let imageURL = root.appendingPathComponent("fixture-render.png")
    try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aU1sAAAAASUVORK5CYII=")!.write(to: imageURL)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let studio = Studio(name: "Fixture Studio", folder: root.path)
    try encoder.encode([studio]).write(to: root.appendingPathComponent("Studios.json"))
    AppPreferences.defaults.set(ProcessInfo.processInfo.environment["FAKE_PROVIDER"]!, forKey: "claudePath")
    AppPreferences.defaults.set(ProcessInfo.processInfo.environment["FAKE_PROVIDER"]!, forKey: "codexPath")
    for index in 0..<40 {
        var record = ConversationRecord(model: "default", effort: "", personality: .neutral)
        if index == 0 { record.id = fixtureID }
        if index == 1 { record.id = backgroundID }
        if index == 1 { record.studioID = studio.id; record.studioFolder = studio.folder }
        record.title = index == 0 ? "Recent Chat" : (index == 1 ? "Background Chat" : "Unopened \(index)")
        record.updatedAt = Date().addingTimeInterval(-Double(index * 60))
        record.sentBrief = String(repeating: "provider instructions ", count: 3000)
        record.pendingHandoff = String(repeating: "private handoff ", count: 3000)
        record.brief = "Keep this brief when a summary refresh arrives."
        record.items = (0..<(index == 0 ? 900 : 100)).map { row in
            DisplayItem(kind: row % 2 == 0 ? .user : .assistant,
                text: "Message \(row). " + String(repeating: "Transcript content. ", count: 100))
        }
        if index == 0 {
            record.items[750] = DisplayItem(kind: .assistant, text: "![Earlier render](\(imageURL.path))")
            record.items[20] = DisplayItem(kind: .questions, text: "An older question", approvalState: .pending,
                questions: [AgentQuestion(id: "q", header: "Choose", question: "Keep this pending card?", options: [], multiSelect: false, isSecret: false)])
        }
        try encoder.encode(record).write(to: folder.appendingPathComponent("\(record.id.uuidString).json"))
    }
    AppPreferences.defaults.set(fixtureID.uuidString, forKey: "macLastOpenSession")
}

@MainActor func run() async throws {
    UserDefaults.standard.setVolatileDomain(["notifyNeeds": false, "notifyReplies": false, "companionEnabled": false], forName: UserDefaults.argumentDomain)
    let started = Date()
    let model = AppModel()
    try await wait("summary list loads") { model.sessions.count == 40 && model.sessionLoadStatus == nil }
    print("METRIC startup \(Date().timeIntervalSince(started)) seconds")
    try check(RuntimeClient.shared.supportsNavigationSummaries, "summary capability negotiated")
    try check(model.selectedID == fixtureID, "latest open session restored")
    let recent = model.sessions.first { $0.id == fixtureID }!
    let background = model.sessions.first { $0.id == backgroundID }!
    try await wait("only selected transcript hydrates") { recent.transcriptLoaded && recent.items.count == 40 }
    try check(model.sessions.filter { !$0.items.isEmpty }.count == 1, "39 unopened sessions retain zero transcript rows")
    try check(recent.transcriptTotalCount == 900 && recent.transcriptStart == 860, "recent page reports earlier history")
    try check(recent.pendingRequests.count == 1, "question outside recent page remains available")
    try check(recent.latestThumbnailURL()?.lastPathComponent == "fixture-render.png", "thumbnail survives outside the recent transcript page")
    try check(background.lastActionSummary != nil && StudioSessionSummary.note(background, limit: 120) != "No replies yet", "unopened rows and Studio cards retain their previews")
    try check(background.hasMessages && model.canFork(background), "unloaded chats remain forkable and nonempty")

    // The retired bulk path can exceed the normal 15 s request budget in a Debug UI.
    // Only this comparison uses a longer timeout; normal navigation stays summary-only.
    let legacy = try await RuntimeClient.shared.request("list", timeout: .seconds(90))
    let summaries = try await RuntimeClient.shared.request("list", body: ["summaryOnly": true])
    let legacyBytes = try legacy.encoded().count, summaryBytes = try summaries.encoded().count
    print("METRIC list legacy=\(legacyBytes) summary=\(summaryBytes) bytes")
    let states = try summaries.decode([RuntimeChatState].self)
    try check(states.allSatisfy { $0.record.items.isEmpty && $0.draft == nil && $0.record.pendingHandoff == nil && $0.record.sentBrief == nil && $0.record.claudeHost == nil }, "summaries exclude transcripts, drafts and provider state")
    try check(summaryBytes < legacyBytes / 10, "summary payload is at least ten times smaller")

    let first = recent.items.first!.id
    model.loadEarlierTranscript(recent)
    try await wait("older page loads on request") { recent.items.count == 80 && !recent.transcriptLoading }
    try check(recent.transcriptStart == 820 && recent.items[40].id == first, "one older chunk prepends without duplicates or losing recent rows")
    try check(Set(recent.items.map(\.id)).count == recent.items.count, "history page IDs remain unique")

    // A global resync must not erase a loaded prefix or a selected chat's Brief.
    _ = try await RuntimeClient.shared.request("preferences", body: ["defaultEffort": "high"])
    try await Task.sleep(for: .milliseconds(350))
    try check(recent.items.count == 80 && recent.record.brief != nil, "configuration resync preserves loaded history and brief")
    // A new Mac may briefly connect to an older daemon before its idle-safe restart.
    // Its first summary resync must also release rows received over that older protocol.
    background.record.items = Array(recent.items.suffix(10)); background.transcriptLoaded = true
    _ = try await RuntimeClient.shared.request("preferences", body: ["defaultEffort": "low"])
    try await wait("summary resync releases rows from the legacy loading path") { background.items.isEmpty && !background.transcriptLoaded }

    model.selectedID = backgroundID
    try await wait("click hydrates the other session") { background.transcriptLoaded && background.items.count == 40 }
    try check(recent.items.isEmpty && !recent.transcriptLoaded, "leaving a chat releases its transcript")
    background.draft = "A draft that must survive switching and reconnect"
    try await Task.sleep(for: .milliseconds(300))
    background.setTitle("Renamed while switching")
    model.selectedID = fixtureID
    try check(background.title == "Renamed while switching", "eviction does not undo a pending rename")
    try await wait("return opens a fresh bounded tail") { recent.transcriptLoaded && recent.items.count == 40 }
    try check(background.draft == "A draft that must survive switching and reconnect", "eviction preserves the local draft")

    _ = try await RuntimeClient.shared.request("settings", body: ["chatID": .string(backgroundID.uuidString), "backend": "codex"])
    try await wait("background settings update via summary") { background.record.backend == .codex }
    try check(background.items.isEmpty, "background event does not hydrate its transcript")

    _ = try await RuntimeClient.shared.request("send", body: ["chatID": .string(backgroundID.uuidString), "text": "hold"])
    try await wait("background working status arrives without loading messages") { background.isRunning && background.items.isEmpty }
    _ = try await RuntimeClient.shared.request("stop", body: ["chatID": .string(backgroundID.uuidString)])
    try await wait("completion updates unread Activity without loading messages") { !background.isRunning && background.items.isEmpty && Attention.shared.unread.contains(backgroundID) }

    model.retainTranscript(background)
    try await wait("another visible window can hydrate its chat") { background.transcriptLoaded }
    model.releaseTranscript(backgroundID)
    try check(background.items.isEmpty, "closing that window releases its transcript")

    model.loadEarlierTranscript(recent, complete: true)
    try await wait("explicit find or library request can read full history") { recent.items.count == 900 && !recent.hasEarlierTranscript }
    RuntimeClient.shared.stop(); RuntimeClient.shared.start()
    try await wait("reconnected") { RuntimeClient.shared.connected }
    try await Task.sleep(for: .milliseconds(400))
    try check(recent.items.count == 900 && Set(recent.items.map(\.id)).count == 900, "reconnect preserves loaded history without duplicates")
    try check(background.items.isEmpty && background.draft == "A draft that must survive switching and reconnect", "reconnect leaves unopened history unloaded and draft intact")

    // An empty navigation record must never be reused as a blank new conversation.
    let new = model.newChat(backend: .claude)
    try check(new.id != fixtureID && new.id != backgroundID, "new chat does not overwrite an unloaded conversation")
    try await wait("new chat is persisted") { FileManager.default.fileExists(atPath: RuntimePaths.data.appendingPathComponent("Conversations/\(new.id.uuidString).json").path) }
    let state = try await RuntimeClient.shared.request("get", body: ["chatID": .string(new.id.uuidString)])
    let newState = try state.decode(RuntimeChatState.self)
    try check(newState.totalCount == 0, "new chat is genuinely empty")
    let studioNew = model.newChat(in: model.studios[0])
    try check(studioNew.id != backgroundID && studioNew.id != fixtureID, "new Studio chat does not reuse an unloaded conversation")

    model.archive(background)
    var archived: RuntimeChatState?
    for _ in 0..<100 {
        let state = try await RuntimeClient.shared.request("get", body: ["chatID": .string(backgroundID.uuidString), "summaryOnly": true]).decode(RuntimeChatState.self)
        if state.record.archivedAt != nil { archived = state; break }
        try await Task.sleep(for: .milliseconds(30))
    }
    try check((archived?.totalCount ?? 0) >= 100, "archiving an unloaded chat retains its messages")
    model.selectedID = fixtureID
    try await wait("selected chat ready for render") { recent.transcriptLoaded }
    try await Task.sleep(for: .seconds(2.5))
    let cacheURL = RuntimePaths.data.appendingPathComponent("mac-navigation.json")
    let cache = try Data(contentsOf: cacheURL)
    let cacheJSON = try JSONSerialization.jsonObject(with: cache) as! [String: Any]
    let cachedStates = cacheJSON["states"] as! [[String: Any]]
    try check(cachedStates.allSatisfy { (($0["record"] as? [String: Any])?["items"] as? [Any])?.isEmpty == true && $0["draft"] == nil }, "disk navigation cache contains no transcript or draft")
    RuntimeClient.shared.stop()
    let restored = AppModel()
    try check(restored.sessions.count == model.sessions.count && restored.sessions.allSatisfy { $0.items.isEmpty }, "cached sidebar restores synchronously without loading messages")
    try check(restored.selectedID == fixtureID, "cached startup preserves the latest open session")
    try await wait("cached selected chat hydrates after connection") { restored.selected?.transcriptLoaded == true }

    let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 1100, height: 780), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: ContentView().environment(restored))
    window.orderFrontRegardless()
    try await Task.sleep(for: .seconds(1))
    if #available(macOS 14.4, *) {
        let target = try await SCShareableContent.currentProcess.windows.first { $0.windowID == CGWindowID(window.windowNumber) }!
        let config = SCStreamConfiguration(); config.width = 1100; config.height = 780; config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: config)
        let dest = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LAZY_CAPTURE"]!)
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: dest)
    }
    // Exercise the real transcript control against the daemon, not just its model method.
    func scrollViews(_ view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }
    let visible = restored.selected!
    guard let scroll = scrollViews(window.contentView!).filter({ $0.bounds.width > 400 }).max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }) else {
        throw RuntimeFailure("Transcript scroll view missing")
    }
    func pressHistory() async throws {
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(150))
        let point = scroll.documentView!.convert(NSPoint(x: scroll.documentView!.bounds.midX, y: 34), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(350))
    }
    let initialHeight = scroll.documentView!.frame.height
    scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
    try await Task.sleep(for: .seconds(1))
    try check(visible.items.count == 40 && abs(scroll.documentView!.frame.height - initialHeight) < 1,
        "reaching the top neither fetches nor reveals older history")
    for _ in 0..<3 {
        try await pressHistory()
    }
    try check(visible.items.count == 40, "explicit clicks reveal already held rows before fetching more")
    try await pressHistory()
    try await wait("explicit click fetches just one forty-item chunk") { visible.items.count == 80 && !visible.transcriptLoading }
    try check(visible.transcriptStart == 820, "UI history request preserves the recent tail")
    try await Task.sleep(for: .milliseconds(500))
    scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
    try await Task.sleep(for: .seconds(1))
    try check(visible.items.count == 80, "newly reached top waits for another explicit click")
    // A daemon list refresh after archiving must not fill the deliberately empty pane.
    let sidebar = restored.studioSidebarID, chats = restored.showingChatsSidebar
    restored.archive(visible)
    var archiveConfirmed = false
    for _ in 0..<100 {
        let archiveState = try await RuntimeClient.shared.request("get", body: ["chatID": .string(visible.id.uuidString), "summaryOnly": true]).decode(RuntimeChatState.self)
        if archiveState.record.archivedAt != nil { archiveConfirmed = true; break }
        try await Task.sleep(for: .milliseconds(100))
    }
    try check(archiveConfirmed, "selected archive reaches the daemon")
    _ = try await RuntimeClient.shared.request("preferences", body: ["defaultEffort": "medium"])
    try await Task.sleep(for: .seconds(1))
    try check(restored.selectedID == nil && restored.studioSidebarID == sidebar && restored.showingChatsSidebar == chats,
              "daemon list refresh preserves the empty archive pane and sidebar")
    if #available(macOS 14.4, *) {
        let target = try await SCShareableContent.currentProcess.windows.first { $0.windowID == CGWindowID(window.windowNumber) }!
        let config = SCStreamConfiguration(); config.width = 1100; config.height = 780; config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: config)
        let dest = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LAZY_CAPTURE"]!).deletingPathExtension().appendingPathExtension("archived.png")
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: dest)
    }
    restored.selectedID = backgroundID
    _ = try await RuntimeClient.shared.request("preferences", body: ["defaultEffort": "high"])
    try await Task.sleep(for: .seconds(1))
    try check(restored.selectedID == backgroundID, "deliberately opening another session resumes normal selection")
    RuntimeClient.shared.stop()
}

Task { @MainActor in
    do {
        if CommandLine.arguments.contains("seed") { try seed() } else { try await run() }
        exit(0)
    } catch { print("FAIL \(error.localizedDescription)"); exit(1) }
}
app.run()
