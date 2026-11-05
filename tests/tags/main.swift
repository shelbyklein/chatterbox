import AppKit
import SwiftUI
import Observation

// Tags on the Mac when the service runs the sessions (scripts/test-tags.sh): a tag added with
// ChatSession.toggleTag reaches the service, survives the service's next update and a full
// list refresh, shows in AppModel.allTags (the Tags menu and the sidebar's filter pills), and
// redraws whatever reads the open sessions' tags.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let projectID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
let chatID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
let sideID = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RuntimeFailure("FAIL \(message)") }
    print("PASS \(message)")
}
@MainActor func wait(_ label: String, seconds: Double = 20, _ predicate: () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !(await predicate()) {
        guard Date() < deadline else { throw RuntimeFailure("Timed out: \(label)") }
        try await Task.sleep(for: .milliseconds(30))
    }
    print("PASS \(label)")
}

@MainActor func seed() throws {
    let root = RuntimePaths.data
    let folder = root.appendingPathComponent("Conversations")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    func write(_ record: ConversationRecord) throws {
        try encoder.encode(record).write(to: folder.appendingPathComponent("\(record.id.uuidString).json"))
    }
    var project = ConversationRecord(model: "default", effort: "", personality: .neutral)
    project.id = projectID; project.title = "Tagged project"
    project.projectFolder = root.appendingPathComponent("project").path; project.projectNickname = "Tag Project"
    project.items = [DisplayItem(kind: .user, text: "Hello"), DisplayItem(kind: .assistant, text: "Hi", phase: .final)]
    try write(project)
    var chat = ConversationRecord(model: "default", effort: "", personality: .neutral)
    chat.id = chatID; chat.title = "Loose chat"; chat.updatedAt = Date().addingTimeInterval(-60)
    chat.items = [DisplayItem(kind: .user, text: "Another")]
    try write(chat)
    var side = ConversationRecord(model: "default", effort: "", personality: .neutral)
    side.id = sideID; side.title = "Side of the project"; side.updatedAt = Date().addingTimeInterval(-120)
    side.sidechatOf = projectID; side.sidechatProjectFolder = project.projectFolder
    side.items = [DisplayItem(kind: .user, text: "Side")]
    try write(side)
    AppPreferences.defaults.set(chatID.uuidString, forKey: "macLastOpenSession")
}

/// What the service has for the chat, as the Mac's list asks for it.
@MainActor func serviceTags(_ id: UUID) async throws -> [String]? {
    try await RuntimeClient.shared.request("get", body: ["chatID": .string(id.uuidString), "summaryOnly": true])
        .decode(RuntimeChatState.self).record.tags
}

/// True once anything `read` touched changes.
@MainActor final class Redraw { var fired = false }
@MainActor func tracking(_ read: @escaping () -> Void) -> Redraw {
    let redraw = Redraw()
    withObservationTracking(read) { Task { @MainActor in redraw.fired = true } }
    return redraw
}


/// The context menu SwiftUI gives the view under `point` (what a right-click there pops up).
@MainActor func contextMenu(_ window: NSWindow, at point: NSPoint) -> NSMenu? {
    let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 7, clickCount: 1, pressure: 1)!
    var view = window.contentView?.hitTest(point)
    while let current = view {
        if let menu = current.menu(for: event) { menu.update(); return menu }
        view = current.superview
    }
    return nil
}
/// Runs the menu's item, as choosing it does; its title.
@MainActor func choose(_ found: (NSMenu, Int)?) -> String? {
    guard let (menu, index) = found else { return nil }
    menu.performActionForItem(at: index)
    return menu.items[index].title
}
/// The Tags submenu's item called `title`.
@MainActor func tagsItem(_ title: String) -> (NSMenu) -> (NSMenu, Int)? {
    { menu in
        guard let tags = menu.items.first(where: { $0.title == "Tags" })?.submenu else { return nil }
        tags.update()
        print("  Tags menu: \(tags.items.map(\.title))")
        return tags.items.firstIndex { $0.title == title }.map { (tags, $0) }
    }
}
@MainActor func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
    (view as? T).map { [$0] } ?? [] + view.subviews.flatMap { views(type, in: $0) }
}

@MainActor func run() async throws {
    UserDefaults.standard.setVolatileDomain(["notifyNeeds": false, "notifyReplies": false, "companionEnabled": false], forName: UserDefaults.argumentDomain)
    let model = AppModel()
    try await wait("session list loads from the service") { model.sessions.count == 3 && model.sessionLoadStatus == nil }
    let project = model.sessions.first { $0.id == projectID }!
    let chat = model.sessions.first { $0.id == chatID }!
    try check(model.allTags.isEmpty, "no tags to begin with")

    // The sidebar's tag pills and the session rows read these; adding a tag must redraw them.
    let pills = tracking { _ = model.allTags }
    let rows = tracking { for session in model.activeSessions { _ = session.tags } }
    project.toggleTag("Alpha")
    try check(project.tags == ["Alpha"], "toggleTag adds the tag on the Mac at once")
    try check(model.allTags == ["Alpha"], "the new tag is in allTags (Tags menu and filter pills)")
    try await wait("the tag pills redraw", seconds: 2) { pills.fired }
    try await wait("the session rows redraw", seconds: 2) { rows.fired }

    try await wait("the service has the tag") { (try? await serviceTags(projectID)) ?? nil == ["Alpha"] }
    // The service's chat.changed comes back and the Mac applies the service's copy.
    try await Task.sleep(for: .seconds(1))
    try check(project.tags == ["Alpha"], "the tag survives the service's update")
    try check(model.allTags == ["Alpha"], "allTags still has it after the update")

    // A second tag, on another chat, through the same path the New Tag… sheet uses.
    chat.toggleTag("beta")
    try await wait("the second tag reaches the service") { (try? await serviceTags(chatID)) ?? nil == ["beta"] }
    try check(model.allTags == ["Alpha", "beta"], "allTags lists both, sorted")

    // A full list refresh (reconnect) applies every session's summary again.
    RuntimeClient.shared.onEvent?(RuntimeEvent(sequence: 0, revision: 0, kind: "runtime.resync"))
    try await Task.sleep(for: .seconds(2))
    try check(project.tags == ["Alpha"] && chat.tags == ["beta"], "tags survive a full list refresh")
    try check(model.allTags == ["Alpha", "beta"], "allTags survives a full list refresh")

    // Removing goes the same way.
    project.toggleTag("alpha")
    try await wait("removing the tag reaches the service") { do { return try await serviceTags(projectID) == nil } catch { return false } }
    try await Task.sleep(for: .seconds(1))
    try check(project.tags.isEmpty && model.allTags == ["beta"], "a removed tag stays removed")

    // The service saved it.
    try await Task.sleep(for: .seconds(1))
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let saved = try decoder.decode(ConversationRecord.self, from: Data(contentsOf: RuntimePaths.data.appendingPathComponent("Conversations/\(chatID.uuidString).json")))
    try check(saved.tags == ["beta"], "the service saved the tag to disk")

    // Sidechats under their parent: the sidebar's grouping still answers after these updates.
    try check(model.sidechats(of: project).map(\.id) == [sideID], "the Sidechat stays under its project")

    // The real sidebar: right-click the project, Tags → an existing tag, then Tags → New Tag….
    let window = NSWindow(contentRect: NSRect(x: 40, y: 60, width: 1000, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: ContentView().environment(model))
    window.orderFrontRegardless()
    try await Task.sleep(for: .seconds(1.5))
    func snapshot(_ name: String) throws {
        let shot = window.contentView!; shot.layoutSubtreeIfNeeded()
        let rep = shot.bitmapImageRepForCachingDisplay(in: shot.bounds)!; shot.cacheDisplay(in: shot.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: RuntimePaths.data.appendingPathComponent(name))
    }
    try snapshot("sidebar-before.png")
    var row: NSPoint?
    for y in stride(from: 680.0, to: 20, by: -8) {
        let point = NSPoint(x: 120, y: y)
        if contextMenu(window, at: point)?.items.contains(where: { $0.title == "Rename Session\u{2026}" }) == true { row = point; break }
    }
    try check(row != nil, "found the session's row in the sidebar")
    try check(chat.tags == ["beta"], "the session starts with its tag")

    try check(choose(tagsItem("New Tag\u{2026}")(contextMenu(window, at: row!)!)) == "New Tag\u{2026}", "Tags menu offers New Tag…")
    func alertWindow() -> NSWindow? {
        window.attachedSheet ?? NSApp.windows.first { $0 !== window && $0.isVisible && !views(NSTextField.self, in: $0.contentView!).filter(\.isEditable).isEmpty }
    }
    try await wait("the New Tag alert opens", seconds: 3) { alertWindow() != nil }
    let alert = alertWindow()!
    let field = views(NSTextField.self, in: alert.contentView!).first { $0.isEditable }!
    alert.makeFirstResponder(field)
    (field.currentEditor() as? NSTextView)?.insertText("gamma", replacementRange: NSRange(location: 0, length: 0))
    try await Task.sleep(for: .milliseconds(300))
    let add = views(NSButton.self, in: alert.contentView!).first { $0.title == "Add" }
    try check(add != nil, "the alert has Add")
    add!.performClick(nil)
    try await wait("New Tag… adds the tag", seconds: 3) { chat.tags == ["beta", "gamma"] }
    try await wait("…and the service has it") { (try? await serviceTags(chatID)) ?? nil == ["beta", "gamma"] }
    try await Task.sleep(for: .seconds(1))
    try check(chat.tags == ["beta", "gamma"] && model.allTags == ["beta", "gamma"], "the new tag stays, and is in allTags")

    // The menu's checkmark item takes a tag off.
    try check(choose(tagsItem("beta")(contextMenu(window, at: row!)!)) == "beta", "Tags menu lists the session's tag")
    try await wait("the menu takes the tag off", seconds: 3) { chat.tags == ["gamma"] }
    try await wait("…and on the service") { (try? await serviceTags(chatID)) ?? nil == ["gamma"] }
    try await Task.sleep(for: .seconds(1))
    try check(chat.tags == ["gamma"] && model.allTags == ["gamma"], "the removal stays")

    // Shelby's case: an existing tag picked from the context menu AppKit pops up. The menu is
    // the one drawn for the row, so it must be current: list a tag another session just got,
    // and tick a tag picked a moment ago, even on a row that doesn't show tags (a pinned
    // thread's). Meanwhile the session keeps changing underneath it, as a working one does.
    let churn = Timer(timeInterval: 0.05, repeats: true) { _ in
        MainActor.assumeIsolated { RuntimeClient.shared.onEvent?(RuntimeEvent(sequence: 0, chatID: chatID, revision: 0, kind: "turn.progress")) }
    }
    RunLoop.main.add(churn, forMode: .common)
    /// Right-clicks at `point`; the Tags submenu as it showed ("✓name" when ticked), after
    /// picking `pick` from it.
    func popUp(at point: NSPoint, pick: String? = nil) -> (tags: [String], top: [String]) {
        var shown: [String] = [], top: [String] = [], picked: (NSMenu, Int)?
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            guard let menu = note.object as? NSMenu, menu.supermenu == nil else { return }
            // Choose after a moment with the menu open, as a person does.
            let choose = Timer(timeInterval: 0.6, repeats: false) { _ in
                MainActor.assumeIsolated {
                    top = menu.items.map(\.title)
                    if let tags = menu.items.first(where: { $0.title == "Tags" })?.submenu {
                        // As hovering Tags does: the submenu is filled in as it opens.
                        tags.delegate?.menuNeedsUpdate?(tags)
                        tags.delegate?.menuWillOpen?(tags)
                        tags.update()
                        shown = tags.items.filter { !$0.isSeparatorItem }.map { ($0.state == .on ? "\u{2713}" : "") + $0.title }
                        if let pick { picked = tags.items.firstIndex { $0.title == pick }.map { (tags, $0) } }
                    }
                    menu.cancelTracking()
                }
            }
            RunLoop.main.add(choose, forMode: .eventTracking)
        }
        for type in [NSEvent.EventType.rightMouseDown, .rightMouseUp] {
            window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil, eventNumber: 9, clickCount: 1, pressure: 1)!)
        }
        NotificationCenter.default.removeObserver(observer)
        _ = choose(picked)
        return (shown, top)
    }

    project.toggleTag("delta")
    try await wait("another session has a new tag", seconds: 3) { model.allTags == ["delta", "gamma"] }
    // A moment, as between a person's clicks: the views take the change on their next update.
    try await Task.sleep(for: .milliseconds(500))
    var menu = popUp(at: row!, pick: "delta")
    print("  row's Tags menu: \(menu.tags)")
    try check(menu.top.contains("Tags"), "the real context menu popped up")
    try check(menu.tags.contains("delta"), "the row's menu lists the tag another session just got")
    try await wait("picking it tags the session", seconds: 3) { chat.tags == ["gamma", "delta"] }
    try await Task.sleep(for: .milliseconds(500))
    menu = popUp(at: row!)
    print("  row's Tags menu again: \(menu.tags)")
    try check(menu.tags.contains("\u{2713}delta") && menu.tags.contains("\u{2713}gamma"), "the row's menu ticks the picked tag")

    // A pinned thread's row (compact, no tag pills).
    model.togglePinnedThread(chat)
    try await Task.sleep(for: .seconds(1))
    var pinned: NSPoint?
    for y in stride(from: 680.0, to: 20, by: -8) {
        let point = NSPoint(x: 120, y: y)
        if contextMenu(window, at: point)?.items.contains(where: { $0.title == "Unpin" }) == true { pinned = point; break }
    }
    try check(pinned != nil, "found the pinned thread's row")
    project.toggleTag("epsilon")
    try await wait("another session has another new tag", seconds: 3) { model.allTags == ["delta", "epsilon", "gamma"] }
    try await Task.sleep(for: .milliseconds(500))
    // (AppKit's popup on this row isn't driven from a test; the menu it shows is this one.)
    func pinnedTags() -> [String] {
        let tags = contextMenu(window, at: pinned!)?.items.first { $0.title == "Tags" }?.submenu
        tags?.update()
        return (tags?.items ?? []).filter { !$0.isSeparatorItem }.map { ($0.state == .on ? "\u{2713}" : "") + $0.title }
    }
    print("  pinned row's Tags menu: \(pinnedTags())")
    try check(pinnedTags().contains("epsilon"), "the pinned row's menu lists the new tag")
    try check(choose(tagsItem("epsilon")(contextMenu(window, at: pinned!)!)) == "epsilon", "picked it from the pinned row's menu")
    try await wait("picking it tags the pinned thread", seconds: 3) { chat.tags == ["gamma", "delta", "epsilon"] }
    try await Task.sleep(for: .milliseconds(500))
    print("  pinned row's Tags menu again: \(pinnedTags())")
    try check(pinnedTags().contains("\u{2713}epsilon"), "the pinned row's menu ticks the tag just picked")
    try await Task.sleep(for: .seconds(2))
    let onService = (try? await serviceTags(chatID)) ?? nil
    print("  after 2 s of updates: Mac \(chat.tags), service \(onService ?? [])")
    try check(chat.tags == ["gamma", "delta", "epsilon"] && onService == ["gamma", "delta", "epsilon"], "the picked tags stay, on the Mac and the service")
    churn.invalidate()
    try snapshot("sidebar-tags.png")
    print("Proof: \(RuntimePaths.data.appendingPathComponent("sidebar-tags.png").path)")
    window.orderOut(nil)
    RuntimeClient.shared.stop()
}

Task { @MainActor in
    do {
        if CommandLine.arguments.contains("seed") { try seed() } else { try await run() }
        exit(0)
    } catch { print(error.localizedDescription); exit(1) }
}
app.run()
