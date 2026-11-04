@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// The Desk on the Mac (plans/front-desk.md, T3): Home's first page, with Needs you from this
// Mac's sessions, Incoming and replies from a stand-in service Desk, and Working. Checks the
// summary line, which sections show, the "desk" requests it sends (get, add, start, ignore,
// silence, places), that Open, Approve, Ignore, Silence and Start there do what they say, that
// cards are named as the session lists name them, and two columns on a wide window.
// Evidence: desk-*.png in the fixture folder.
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { failures += 1 } }

@MainActor func run() async throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
    precondition(root.path.hasPrefix("/tmp/chatterbox-mac-desk."))
    UserDefaults.standard.setVolatileDomain(["companionEnabled": false, "notifyNeeds": false, "notifyFinished": false, "keepMacAwake": false,
                                             "sidebarProjectsCollapsed": false, "sidebarStudiosCollapsed": false, "sidebarChatsCollapsed": false],
                                            forName: UserDefaults.argumentDomain)
    precondition(Bundle.main.bundleIdentifier != "com.shelbyklein.Chatterbox")
    defer { for key in ["macStudioSelection", "macStudioInspected"] { UserDefaults.standard.removeObject(forKey: key) } }
    let now = Date()

    // MARK: Pure logic: the summary line and which sections show.
    check(DeskSections.summary(needsYou: 2, incoming: 0, working: 3) == "2 need you · 3 working", "summary: 2 need you · 3 working")
    check(DeskSections.summary(needsYou: 1, incoming: 2, working: 0) == "1 needs you · 2 incoming", "summary: singular, and incoming")
    check(DeskSections.summary(needsYou: 0, incoming: 0, working: 0) == "All clear", "summary: nothing at all")
    var logic = DeskSections()
    check(logic.visible.isEmpty && logic.isCalm, "empty Desk: no sections, calm")
    logic.working = [Companion.DeskWorking(id: UUID(), title: "Ribbons", place: nil)]
    check(logic.visible == [.working] && logic.isCalm, "only Working: still calm (Nothing else needs you.)")
    let sample = Companion.DeskRequest(id: UUID(), text: "x", source: "claude", createdAt: now.addingTimeInterval(-300), proposed: nil)
    logic.incoming = [sample]
    check(logic.visible == [.incoming, .working] && !logic.isCalm, "Incoming before Working; not calm")
    logic.needsYou = [DeskNeed(waiting: .init(id: UUID(), chatID: UUID(), title: "t", place: nil, kind: "approval", text: "a"))]
    check(logic.visible == [.needsYou, .incoming, .working] && logic.actionCount == 2, "Needs you first; badge counts needs and incoming")
    let startedID = UUID()
    check(DeskModel.startedSessionID(["revision": 3, "summary": ["id": .string(startedID.uuidString), "title": "x"]]) == startedID, "start reply: ChatDetail's summary id")
    check(DeskModel.startedSessionID(["id": .string(startedID.uuidString)]) == startedID && DeskModel.startedSessionID(.string(startedID.uuidString)) == startedID, "start reply: a bare id")
    check(DeskModel.startedSessionID(["summary": ["title": "x"]]) == nil, "start reply without an id: nothing to open")
    check(DeskText.origin(sample, now: now) == "From Claude · 5m", "origin line: \(DeskText.origin(sample, now: now))")
    var mine = sample; mine.source = "you"; mine.createdAt = now.addingTimeInterval(-30)
    check(DeskText.origin(mine, now: now) == "From you · now", "origin line from you: \(DeskText.origin(mine, now: now))")
    let line = DeskText.detailLine("# USA Archery\n\n- **Brand:** navy and red\n```\ncode\n```\n- Use the [2027 logo](https://x)")
    check(line == "Brand: navy and red Use the 2027 logo", "place detail as plain text: \(line ?? "nil")")

    // MARK: Fixture sessions.
    let model = AppModel()
    func record(_ title: String, _ backend: Backend = .claude) -> ConversationRecord {
        var r = ConversationRecord(model: "opus", effort: "medium", personality: .pragmatic)
        r.title = title; r.activeBackend = backend
        return r
    }
    let usa = model.newStudio(named: "USA Archery")!
    func inStudio(_ r: ConversationRecord) -> ConversationRecord { var r = r; r.studioID = usa.id; r.studioFolder = usa.folder; return r }
    var magazineRecord = inStudio(record("2027 Indoor Magazine"))
    let approvalID = UUID()
    magazineRecord.items = [
        DisplayItem(kind: .assistant, timestamp: now.addingTimeInterval(-700), text: "The cover proof is ready.", phase: .final),
        DisplayItem(id: approvalID, kind: .approval, timestamp: now.addingTimeInterval(-600), text: "Claude wants to run a command",
                    detail: "npm run proof && open dist/indoor-2027.pdf", requestID: ["id": "r1", "tool": "Bash", "input": [:]], approvalState: .pending),
    ]
    let magazine = model.insertSession(magazineRecord)
    var planRecord = record("Mac Desk page")
    planRecord.projectFolder = root.appendingPathComponent("Chatterbox").path; planRecord.projectNickname = "Chatterbox"
    planRecord.items = [DisplayItem(kind: .approval, timestamp: now.addingTimeInterval(-300), text: "Claude has a plan. Start building?",
                                    detail: "# Plan\n\nAdd the Desk as Home's first page, with Needs you, Incoming and Working. Then wire desk.changed.",
                                    requestID: ["id": "r2", "tool": "ExitPlanMode", "input": [:]], approvalState: .pending, approvalStyle: .plan)]
    let plan = model.insertSession(planRecord)
    plan.isRunning = true   // waiting on its plan while its turn is open: Needs you, not Working
    var magnetsRecord = record("PlayCase magnets", .codex)
    magnetsRecord.items = [DisplayItem(kind: .questions, timestamp: now.addingTimeInterval(-120), requestID: .string("q1"), approvalState: .pending, questions: [
        AgentQuestion(id: "size", header: "Magnet size", question: "Which magnet size should the case use?",
                      options: [.init(label: "6 mm", detail: "Stronger"), .init(label: "5 mm", detail: "Fits the current lid")], multiSelect: false, isSecret: false),
        AgentQuestion(id: "count", header: "Count", question: "How many per case?", options: [], multiSelect: false, isSecret: false),
    ])]
    let magnets = model.insertSession(magnetsRecord)
    var logosRecord = inStudio(record("Event Logos"))
    logosRecord.items = [DisplayItem(kind: .assistant, timestamp: now.addingTimeInterval(-60), text: "Here are both directions. Which of the two marks should I take forward?", phase: .final)]
    let logos = model.insertSession(logosRecord)
    let ribbons = model.insertSession(inStudio(record("National Event Ribbons", .codex)))
    ribbons.isRunning = true
    var sdhqRecord = record("Menu refresh")
    sdhqRecord.projectFolder = root.appendingPathComponent("SDHQ").path; sdhqRecord.projectNickname = "SDHQ"
    let sdhq = model.insertSession(sdhqRecord)
    sdhq.isRunning = true
    var archivedRecord = record("Archived with a question")
    archivedRecord.archivedAt = now
    archivedRecord.items = [DisplayItem(kind: .approval, text: "Old request", requestID: ["id": "r9"], approvalState: .pending)]
    let archived = model.insertSession(archivedRecord)
    let chatterbox = Companion.DeskPlace(kind: "project", id: plan.id, name: "Chatterbox", detail: "The Chatterbox Mac app, its service, and the iPhone app.")
    let usaPlace = Companion.DeskPlace(kind: "studio", id: usa.id, name: "USA Archery",
                                       detail: "# USA Archery\n\nMarketing for USA Archery: member emails, the magazine, event graphics and ribbons.")
    let places = [usaPlace, chatterbox,
                  Companion.DeskPlace(kind: "studio", id: UUID(), name: "Geekify", detail: "Fan art and painting commissions."),
                  Companion.DeskPlace(kind: "project", id: sdhq.id, name: "SDHQ", detail: "The SDHQ restaurant site and menus.")]

    // MARK: The stand-in service Desk and transport.
    let resultsEmail = Companion.DeskRequest(id: UUID(), text: "Draft the 2027 Indoor Nationals results email to members", source: "claude",
                                             createdAt: now.addingTimeInterval(-1500), proposed: usaPlace,
                                             note: "Results post Friday; Lauren wants the email ready to send that afternoon.")
    let badge = Companion.DeskRequest(id: UUID(), text: "Fix the iPad sidebar badge count after archiving a session", source: "you",
                                      createdAt: now.addingTimeInterval(-240), proposed: chatterbox)
    let order = Companion.DeskRequest(id: UUID(), text: "Order more 6 mm magnets before the next PlayCase batch", source: "you",
                                      createdAt: now.addingTimeInterval(-60), proposed: nil)
    var service = Companion.Desk(revision: 4, needsYou: [
        .init(id: logos.id, chatID: logos.id, title: "Event Logos", place: "USA Archery", kind: "reply", text: "Which of the two marks should I take forward?"),
        // The service's own copy of an approval the Mac already has: shown once.
        .init(id: approvalID, chatID: magazine.id, title: "2027 Indoor Magazine", place: "USA Archery", kind: "approval", text: "Claude wants to run a command"),
        // A reply from a session that's working again, and one for a session this Mac doesn't have.
        .init(id: ribbons.id, chatID: ribbons.id, title: "National Event Ribbons", place: nil, kind: "reply", text: "Stale?"),
        .init(id: UUID(), chatID: UUID(), title: "Gone", place: nil, kind: "reply", text: "Gone?"),
    ], incoming: [resultsEmail, badge, order], working: [])
    var sent: [JSON] = []
    let desk = DeskModel.shared
    desk.transport = { body, _ in
        sent.append(body)
        let id = body["id"]?.string.flatMap(UUID.init(uuidString:))
        switch body["action"]?.string {
        case "get": return try JSON.value(service)
        case "places": return try JSON.value(places)
        case "add":
            service.incoming.append(.init(id: UUID(), text: body["text"]?.string ?? "", source: body["source"]?.string ?? "?", createdAt: Date(), proposed: usaPlace))
            service.revision += 1
            return try JSON.value(service)
        case "ignore":
            service.incoming.removeAll { $0.id == id }; service.revision += 1
            return try JSON.value(service)
        case "silence":
            // As the service does: a reply it lists, or an approval in the session, goes to silenced.
            let chat = body["chatID"]?.string.flatMap(UUID.init(uuidString:))
            if let index = service.needsYou.firstIndex(where: { $0.id == id && $0.chatID == chat }) {
                service.silenced = (service.silenced ?? []) + [service.needsYou.remove(at: index)]
            } else if let session = model.sessions.first(where: { $0.id == chat }), let item = session.pendingRequests.first(where: { $0.id == id }) {
                service.silenced = (service.silenced ?? []) + [.init(id: item.id, chatID: session.id, title: session.title, place: nil, kind: "approval", text: item.text)]
            }
            service.revision += 1
            return try JSON.value(service)
        case "start":
            service.incoming.removeAll { $0.id == id }; service.revision += 1
            return ["revision": 1, "summary": ["id": .string(startedID.uuidString), "title": "Fix the iPad sidebar badge"], "settings": "Claude", "items": [], "earlierCount": 0]
        default: throw RuntimeFailure("unsupported_operation")
        }
    }
    desk.load(service)

    // MARK: What the Desk shows.
    let sections = desk.sections(in: model)
    let needs = sections.needsYou
    check(Set(needs.map(\.waiting.chatID)) == Set([magazine.id, plan.id, magnets.id, logos.id]) && needs.count == 4,
          "Needs you: approval, plan, questions and the service's reply, each session once (\(needs.map(\.waiting.title)))")
    check(!needs.contains { $0.waiting.chatID == archived.id || $0.waiting.chatID == ribbons.id }, "archived sessions and stale replies left out")
    let byChat = Dictionary(uniqueKeysWithValues: needs.map { ($0.waiting.chatID, $0) })
    check(byChat[magazine.id]?.waiting.kind == "approval" && byChat[magazine.id]?.detail == "npm run proof && open dist/indoor-2027.pdf"
          && byChat[magazine.id]?.waiting.place == "USA Archery", "approval: its command, in its Studio")
    check(byChat[plan.id]?.waiting.kind == "plan" && byChat[plan.id]?.waiting.text == "Add the Desk as Home's first page, with Needs you, Incoming and Working."
          && byChat[plan.id]?.waiting.place == "Chatterbox", "plan: its first sentence, in its project (\(byChat[plan.id]?.waiting.text ?? ""))")
    check(byChat[magnets.id]?.waiting.kind == "questions" && byChat[magnets.id]?.waiting.text == "Which magnet size should the case use? (and 1 more)"
          && byChat[magnets.id]?.waiting.place == nil, "questions: the first, and how many more")
    check(byChat[logos.id]?.waiting.kind == "reply" && byChat[logos.id]?.canDecide == false, "reply: from the service, opened rather than approved")
    let planIndex = needs.firstIndex { $0.waiting.chatID == plan.id }!, magazineIndex = needs.firstIndex { $0.waiting.chatID == magazine.id }!
    check(needs.firstIndex { $0.waiting.chatID == magnets.id }! < planIndex && planIndex < magazineIndex, "newest first, as the phone's Desk")
    check(Set(sections.working.map(\.id)) == Set([ribbons.id, sdhq.id]), "Working: running sessions, not ones waiting on you")
    check(sections.working.first { $0.id == sdhq.id }?.place == "SDHQ", "Working shows the place")
    check(sections.incoming.map(\.id) == [resultsEmail.id, badge.id, order.id], "Incoming: the service's requests")
    check(sections.summary == "4 need you · 3 incoming · 2 working", "header: \(sections.summary)")
    check(desk.badgeCount(in: model) == 7, "toolbar badge: needs and incoming")
    // Named as the session lists name them: a project's session by its project, its title under that.
    check(byChat[plan.id]?.waiting.title == "Chatterbox" && byChat[plan.id]?.waiting.subtitle == "Mac Desk page",
          "a project's session: its project's name, its own title under it (\(byChat[plan.id]?.waiting.title ?? ""))")
    check(byChat[magazine.id]?.waiting.title == "2027 Indoor Magazine" && byChat[magazine.id]?.waiting.subtitle == nil
          && byChat[logos.id]?.waiting.title == "Event Logos", "a Studio's session: its own title")
    let menu = sections.working.first { $0.id == sdhq.id }
    check(menu?.title == "SDHQ" && menu?.subtitle == "Menu refresh", "Working names a project's session by its project too")
    // Silenced on another device: the service lists it, and this Mac leaves it out (not Working either).
    var fromPhone = service
    fromPhone.silenced = [.init(id: magnets.items[0].id, chatID: magnets.id, title: "PlayCase magnets", place: nil, kind: "questions", text: "Which magnet size?")]
    desk.load(fromPhone)
    let phoneSilenced = desk.sections(in: model)
    check(!phoneSilenced.needsYou.contains { $0.waiting.chatID == magnets.id } && phoneSilenced.needsYou.count == 3
          && !phoneSilenced.working.contains { $0.id == magnets.id } && desk.badgeCount(in: model) == 6,
          "silenced elsewhere: off this Mac's Desk and its badge")
    desk.load(service)

    // MARK: Renders.
    // A window per render: each ContentView puts its own toolbar on its window.
    var panel = NSPanel(contentRect: NSRect(x: 40, y: 90, width: 1500, height: 950), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    func render(_ view: AnyView, _ width: CGFloat, _ height: CGFloat, _ name: String, dark: Bool = true) async throws {
        DeskDebug.frames = [:]; MacHomeDebug.entries = [:]
        panel.orderOut(nil)
        panel = NSPanel(contentRect: NSRect(x: 40, y: 90, width: width, height: height), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        panel.setContentSize(NSSize(width: width, height: height)); panel.setFrameOrigin(NSPoint(x: 20, y: 20))
        panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        panel.contentView = NSHostingView(rootView: view.environment(model).environment(\.colorScheme, dark ? .dark : .light))
        try await Task.sleep(for: .milliseconds(800))
        try snapshot(name)
    }
    func snapshot(_ name: String) throws {
        let content = panel.contentView!; content.layoutSubtreeIfNeeded()
        let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name + ".png"))
    }
    func click(_ key: String) async throws {
        guard let frame = DeskDebug.frames[key] else { check(false, "nothing to click at \(key)"); return }
        let point = NSPoint(x: frame.midX, y: panel.frame.height - frame.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            app.postEvent(event, atStart: false)
        }
        try await Task.sleep(for: .milliseconds(500))
    }
    func frame(_ key: String) -> CGRect? { DeskDebug.frames[key] }

    // Home opens on the Desk when it's chosen; the Desk is the column's first entry.
    model.showDesk()
    check(model.showingHome && model.showingDesk && StudioSelection.saved == .desk, "Go > Desk opens Home on the Desk")
    try await render(AnyView(ContentView()), 1500, 950, "desk-home-wide")
    check(frame("section:needsYou") != nil && frame("section:incoming") != nil && frame("section:working") != nil && frame("calm") == nil,
          "all three sections show, no empty state")
    if let a = frame("section:needsYou"), let b = frame("section:incoming"), let c = frame("section:working") {
        check(a.maxY <= b.minY && b.maxY <= c.minY, "sections in order: Needs you, Incoming, Working")
    }
    if let deskEntry = MacHomeDebug.entries["desk"], let pinned = MacHomeDebug.entries["pinned"] {
        check(deskEntry.maxY <= pinned.minY && deskEntry.maxX <= MacHomeDebug.column.maxX + 1, "Desk is the first entry in Home's left column")
    } else { check(false, "Desk and Pinned entries in Home's column") }
    check(frame("chip:\(order.id)") != nil && frame("change:\(order.id)") == nil, "no place: Choose a place, no Change place")
    check(frame("change:\(badge.id)") != nil && frame("approve:\(approvalID)") != nil && frame("open:\(magnets.items[0].id)") != nil, "Change place, Approve and Open are there")
    check(needs.allSatisfy { frame("silence:\($0.id)") != nil }, "every Needs you row has Silence")
    check(frame("subtitle:\(plan.items[0].id)") != nil && frame("subtitle:\(approvalID)") == nil, "a project's session shows its own title under the project's")
    check(panel.title == "Desk", "window title on the Desk (\(panel.title))")
    let rightmost = DeskDebug.frames.values.map(\.maxX).max() ?? 0
    check(rightmost <= 1500 + 1, "nothing clips on the right (\(rightmost))")
    try await render(AnyView(DeskView().background(Color(nsColor: .windowBackgroundColor))), 1080, 940, "desk-light", dark: false)
    let first = needs[0].id, second = needs[1].id
    if let a = frame("needs:\(first)"), let b = frame("needs:\(second)") {
        check(b.minY >= a.maxY, "a 1080-point page: one column")
    } else { check(false, "Needs you rows on the 1080-point page") }
    try await render(AnyView(DeskView().background(Color(nsColor: .windowBackgroundColor))), 1440, 900, "desk-two-column")
    if let a = frame("needs:\(first)"), let b = frame("needs:\(second)"), let c = frame("request:\(resultsEmail.id)"), let d = frame("request:\(badge.id)") {
        check(abs(a.minY - b.minY) < 1 && a.maxX < b.minX && abs(a.height - b.height) < 1, "a wide page: Needs you in two columns, side by side, as tall as each other")
        check(abs(c.minY - d.minY) < 1 && c.maxX < d.minX && abs(c.minX - a.minX) < 1, "and Incoming in the same two columns")
        check(DeskView.columns(for: 1440) == 2 && DeskView.columns(for: 1080) == 1, "two columns past 1100 points of content")
    } else { check(false, "rows on the wide page") }
    let wideRight = DeskDebug.frames.values.map(\.maxX).max() ?? 0
    check(wideRight <= 1440 + 1, "two columns: nothing clips (\(wideRight))")
    try await render(AnyView(ContentView()), 900, 900, "desk-home-narrow", dark: false)
    let narrowRight = DeskDebug.frames.filter { $0.key.hasPrefix("ignore:") || $0.key.hasPrefix("open:") }.values.map(\.maxX).max() ?? 0
    check(narrowRight <= 900 + 1, "narrow window: row buttons stay inside (\(narrowRight))")

    // Change place: every place with what belongs there, and a loose session last.
    try await render(AnyView(DeskPlacePicker(request: badge, desk: desk) {}.background(Color(nsColor: .windowBackgroundColor))), 380, 470, "desk-places")
    check(desk.places.count == places.count && desk.placeOptions.last?.kind == "loose", "places loaded from the service, loose last")
    check(sent.contains { $0["action"]?.string == "places" }, "asked the service for places")

    // MARK: Actions.
    // Open a question: selects its session and leaves Home.
    model.showDesk()
    try await render(AnyView(ContentView()), 1500, 950, "desk-before-actions")
    try await click("open:\(magnets.items[0].id)")
    check(model.selectedID == magnets.id && !model.showingHome, "Open selects the session")

    // Approve: the session's own resolveApproval (no Claude process here, so it expires).
    model.showDesk()
    try await render(AnyView(ContentView()), 1500, 950, "desk-approve")
    try await click("approve:\(approvalID)")
    check(magazine.items.first { $0.id == approvalID }?.approvalState == .expired, "Approve answers the session's approval card")
    check(!desk.sections(in: model).needsYou.contains { $0.id == approvalID }, "an answered approval leaves the Desk")

    // Ignore: {action: ignore, id}.
    try await click("ignore:\(order.id)")
    check(sent.last == ["action": "ignore", "id": .string(order.id.uuidString)], "Ignore sends ignore with the request's id (\(String(describing: sent.last)))")
    check(!desk.sections(in: model).incoming.contains { $0.id == order.id }, "an ignored request leaves the Desk")

    // Silence: {action: silence, chatID, id (and a reply's question)}; off the Desk, still waiting.
    try await click("silence:\(logos.id)")
    check(sent.last == ["action": "silence", "chatID": .string(logos.id.uuidString), "id": .string(logos.id.uuidString),
                        "text": "Which of the two marks should I take forward?"], "Silence sends the reply's chat, id and question (\(String(describing: sent.last)))")
    check(!desk.sections(in: model).needsYou.contains { $0.waiting.chatID == logos.id }, "a silenced reply leaves the Desk")
    let planItem = plan.items[0].id
    try await click("silence:\(planItem)")
    check(sent.last == ["action": "silence", "chatID": .string(plan.id.uuidString), "id": .string(planItem.uuidString)], "a plan's Silence sends its chat and item")
    let quiet = desk.sections(in: model)
    check(!quiet.needsYou.contains { $0.waiting.chatID == plan.id } && !quiet.working.contains { $0.id == plan.id }, "a silenced plan leaves Needs you, and isn't Working")
    check(plan.pendingRequests.map(\.id) == [planItem] && plan.items[0].approvalState == .pending, "and stays pending in its session")
    try snapshot("desk-silenced")

    // Change place, then Start there: {action: start, id, place}, then the new session opens once listed.
    let geekify = places[2]
    desk.choose(geekify, for: badge)
    try await Task.sleep(for: .milliseconds(300))
    try snapshot("desk-changed-place")
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(600))
        var started = record("Fix the iPad sidebar badge"); started.id = startedID
        _ = model.insertSession(started)
    }
    try await click("start:\(badge.id)")
    let start = sent.last { $0["action"]?.string == "start" }
    check(start?["id"]?.string == badge.id.uuidString && (try? start?["place"]?.decode(Companion.DeskPlace.self)) == geekify,
          "Start there sends start with the id and the chosen place (\(String(describing: start)))")
    for _ in 0..<30 where model.selectedID != startedID { try await Task.sleep(for: .milliseconds(100)) }
    check(model.selectedID == startedID && !model.showingHome, "the started session opens once the app has it")
    check(!desk.sections(in: model).incoming.contains { $0.id == badge.id }, "a started request leaves the Desk")

    // The ask box: {action: add, text, source: you}.
    let added = await desk.add("  Book the venue for the 2028 Indoor Nationals  ")
    check(added && sent.last == ["action": "add", "text": "Book the venue for the 2028 Indoor Nationals", "source": "you"], "Add sends the trimmed text from you")
    check(desk.snapshot?.incoming.contains { $0.text == "Book the venue for the 2028 Indoor Nationals" } == true, "the added request shows")

    // desk.changed: with the Desk, it's used as is; without, the Desk asks again.
    var pushed = service; pushed.revision = 40; pushed.incoming = [resultsEmail]
    desk.runtimeEvent(RuntimeEvent(sequence: 1, revision: 0, kind: "desk.changed", payload: try JSON.value(pushed)))
    check(desk.snapshot?.revision == 40 && desk.snapshot?.incoming.map(\.id) == [resultsEmail.id], "desk.changed with a Desk replaces it")
    let before = sent.count
    desk.runtimeEvent(RuntimeEvent(sequence: 2, revision: 0, kind: "desk.changed"))
    try await Task.sleep(for: .milliseconds(200))
    check(sent.count == before + 1 && sent.last == ["action": "get"], "desk.changed without one asks for the Desk")

    // An older service: no Desk operation. Said once, quietly; no retrying until it reconnects.
    var calls = 0
    let old = DeskModel(transport: { _, _ in calls += 1; throw RuntimeFailure("unsupported_operation") })
    old.refresh(); try await Task.sleep(for: .milliseconds(200))
    old.refresh(); try await Task.sleep(for: .milliseconds(200))
    check(old.unsupported && calls == 1 && old.problem?.contains("restarts") == true, "older service: one try, a quiet note")
    old.runtimeEvent(RuntimeEvent(sequence: 3, revision: 0, kind: "runtime.resync")); try await Task.sleep(for: .milliseconds(200))
    check(calls == 2, "reconnecting tries again")

    // MARK: Calm: nothing waits on you or to be placed; Working stays as one line.
    for session in model.sessions {
        let pending = Set(session.pendingRequests.map(\.id))
        for index in session.record.items.indices where pending.contains(session.record.items[index].id) {
            session.record.items[index].approvalState = .denied
        }
    }
    service.needsYou = []; service.incoming = []; service.revision = 50
    desk.load(service)
    model.showDesk()
    try await render(AnyView(ContentView()), 1500, 950, "desk-calm-working")
    check(frame("calm") != nil && frame("section:working") != nil && frame("section:needsYou") == nil && frame("section:incoming") == nil,
          "calm with work going: Nothing else needs you, and the Working line")
    check(desk.sections(in: model).summary == "3 working", "header: 3 working, the plan's session too once answered (\(desk.sections(in: model).summary))")
    ribbons.isRunning = false; sdhq.isRunning = false; plan.isRunning = false
    try await render(AnyView(ContentView()), 1500, 950, "desk-empty")
    check(frame("calm") != nil && frame("section:working") == nil && desk.sections(in: model).summary == "All clear", "empty: only Nothing else needs you")

    // Home's other pages are unchanged: Pinned still opens with its own title.
    UserDefaults.standard.set("pinned", forKey: "macStudioSelection")
    try await render(AnyView(ContentView()), 1500, 950, "studios-pinned-after-desk")
    check(!model.showingDesk && frame("calm") == nil && panel.title == "Studios", "Pinned shows the Studios page again (\(panel.title))")
    StudioSelection.save(.desk)
    model.showStudiosOverview()
    check(StudioSelection.saved == .pinned && model.showingHome && !model.showingDesk, "Command Center's Studios opens the Studios page, not the Desk")

    panel.orderOut(nil)
    print(failures == 0 ? "PASS: the Desk — summary, sections and their order, empty state, local Needs you and Working, service Incoming and replies, Open/Approve/Ignore/Start there/Add, desk.changed, older service. Proof: \(root.path)"
                        : "FAIL: \(failures) checks failed. Renders: \(root.path)")
}
Task { @MainActor in
    do { try await run(); exit(failures == 0 ? 0 : 1) } catch { print("FAIL: \(error)"); exit(1) }
}
app.run()
