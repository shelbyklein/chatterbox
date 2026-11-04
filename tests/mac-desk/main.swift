@testable import ChatterboxTestEngine
import AppKit
import SwiftUI
// The Desk on the Mac (plans/front-desk.md, T3; plans/desk-board.md, B3): Home's first page, a
// board of five columns (To do, Working, Needs you, Ready to mark complete, Done) with Needs you
// and Working from this Mac's sessions, and To do, replies, Ready and Done from a stand-in
// service Desk. Checks the summary line, the columns and their counts and empty lines, the
// "desk" requests it sends (get, add, start, ignore, silence, complete, reopen, places,
// threads, options), that Open, Approve, Ignore, Silence, Mark complete, Reopen and Start there
// do what they say (Start there's step: continue a session already there, or pick the model;
// it runs in the background with a note, nothing opens), that cards are named as the session
// lists name them, and that the board scrolls sideways in a narrow window.
// Evidence: desk-*.png in the fixture folder (desk-board.png: every column with cards).
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

    // MARK: Pure logic: the summary line, the columns and their counts.
    check(DeskSections.summary(needsYou: 2, incoming: 0, working: 3) == "2 need you · 3 working", "summary: 2 need you · 3 working")
    check(DeskSections.summary(needsYou: 1, incoming: 2, working: 0, ready: 4) == "1 needs you · 2 to do · 4 ready", "summary: singular, to do and ready")
    check(DeskSections.summary(needsYou: 0, incoming: 0, working: 0) == "All clear", "summary: nothing at all")
    check(DeskSections.Section.allCases.map(\.rawValue) == ["To do", "Working", "Needs you", "Ready to mark complete", "Done"], "five columns, left to right")
    var logic = DeskSections()
    check(DeskSections.Section.allCases.allSatisfy { logic.count($0) == 0 } && logic.actionCount == 0, "empty Desk: every column empty")
    logic.working = [Companion.DeskWorking(id: UUID(), title: "Ribbons", place: nil)]
    let sample = Companion.DeskRequest(id: UUID(), text: "x", source: "claude", createdAt: now.addingTimeInterval(-300), proposed: nil)
    logic.incoming = [sample]
    logic.needsYou = [DeskNeed(waiting: .init(id: UUID(), chatID: UUID(), title: "t", place: nil, kind: "approval", text: "a"))]
    logic.ready = [.init(id: UUID(), title: "r", place: nil, text: "Done.", finishedAt: now)]
    check(logic.count(.todo) == 1 && logic.count(.working) == 1 && logic.count(.ready) == 1 && logic.count(.done) == 0
          && logic.actionCount == 2, "counts per column; the badge counts needs and to do, not ready")
    check(DeskText.ago(now.addingTimeInterval(-300), now: now) == "5m ago" && DeskText.ago(now, now: now) == "just now", "ages: 5m ago, just now")
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
    // Ready to mark complete and Done (the service's), as this Mac has those sessions.
    func finishedRecord(_ title: String, _ said: String, ago: TimeInterval) -> ConversationRecord {
        var r = record(title)
        r.items = [DisplayItem(kind: .user, text: "Go"), DisplayItem(kind: .assistant, timestamp: now.addingTimeInterval(-ago), text: said, phase: .final)]
        return r
    }
    let proofs = model.insertSession(inStudio(finishedRecord("Banner proofs", "The three banner proofs are in the Studio folder.", ago: 1800)))
    let lid = model.insertSession(finishedRecord("PlayCase lid fit", "The 5 mm magnets fit the current lid with room to spare.", ago: 7200))
    var reArchived = finishedRecord("Archived since", "Done.", ago: 600); reArchived.archivedAt = now
    let readyArchived = model.insertSession(reArchived)
    var flyersRecord = inStudio(finishedRecord("Camp flyers", "Sent to print.", ago: 86_400)); flyersRecord.archivedAt = now.addingTimeInterval(-3600)
    let flyers = model.insertSession(flyersRecord)
    let reopenedElsewhere = model.insertSession(finishedRecord("Reopened elsewhere", "Done.", ago: 90_000))
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
    ], incoming: [resultsEmail, badge, order], working: [],
    ready: [
        .init(id: proofs.id, title: "Banner proofs", place: "USA Archery", text: "The three banner proofs are in the Studio folder.", finishedAt: now.addingTimeInterval(-1800)),
        .init(id: lid.id, title: "PlayCase lid fit", place: nil, text: "The 5 mm magnets fit the current lid with room to spare.", finishedAt: now.addingTimeInterval(-7200)),
        // Working again here, and archived here since: left out before the service says so.
        .init(id: ribbons.id, title: "National Event Ribbons", place: "USA Archery", text: "Old.", finishedAt: now.addingTimeInterval(-9000)),
        .init(id: readyArchived.id, title: "Archived since", place: nil, text: "Done.", finishedAt: now.addingTimeInterval(-600)),
    ],
    done: [
        .init(id: flyers.id, title: "Camp flyers", place: "USA Archery", completedAt: now.addingTimeInterval(-3600)),
        // Unarchived here since: left out.
        .init(id: reopenedElsewhere.id, title: "Reopened elsewhere", place: nil, completedAt: now.addingTimeInterval(-7200)),
    ])
    // Start there's step: sessions already in the place like the work, and a new session's options.
    let sameWork = Companion.DeskThread(id: plan.id, title: "Mac Desk page", detail: "Add the Desk as Home's first page", settings: "Claude · Opus 5.5 · High",
                                        updatedAt: now.addingTimeInterval(-300), isRunning: true, match: "clear")
    let similar = Companion.DeskThread(id: sdhq.id, title: "Menu refresh", settings: "Codex · GPT-6.1-Sol", updatedAt: now.addingTimeInterval(-900), isRunning: false, match: "possible")
    func options(_ picks: Companion.SettingsRequest) -> Companion.ChatOptions {
        let codex = picks.backend == "codex"
        return .init(backend: codex ? "codex" : "claude", model: picks.model ?? (codex ? "" : "opus"), effort: picks.effort ?? "medium",
                     claudeModels: [.init(id: "opus", name: "Opus 5.5", detail: "Most capable", efforts: ["low", "medium", "high"], defaultEffort: "medium"),
                                    .init(id: "sonnet", name: "Sonnet 5", detail: "Fast", efforts: ["low", "medium", "high"], defaultEffort: "medium")],
                     codexModels: [.init(id: "", name: "Codex default", detail: "", efforts: [], defaultEffort: nil),
                                   .init(id: "gpt-6.1-sol", name: "GPT-6.1-Sol", detail: "", efforts: ["low", "medium", "high"], defaultEffort: "medium")],
                     modes: [], mode: "default", presets: [], openModels: [.init(id: "qwen3.5:9b", name: "qwen3.5:9b", detail: "On Shelby-PC", efforts: [], defaultEffort: nil)],
                     openModel: picks.openModel)
    }
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
        case "complete":
            // As the service does: archived, from Ready to Done.
            let chat = body["chatID"]?.string.flatMap(UUID.init(uuidString:))
            guard let index = service.ready?.firstIndex(where: { $0.id == chat }), let item = service.ready?.remove(at: index) else { throw RuntimeFailure("That session is gone.") }
            model.sessions.first { $0.id == chat }?.record.archivedAt = Date()
            service.done = [.init(id: item.id, title: item.title, place: item.place, completedAt: Date())] + (service.done ?? [])
            service.revision += 1
            return try JSON.value(service)
        case "reopen":
            let chat = body["chatID"]?.string.flatMap(UUID.init(uuidString:))
            service.done?.removeAll { $0.id == chat }
            model.sessions.first { $0.id == chat }?.record.archivedAt = nil
            service.revision += 1
            return try JSON.value(service)
        case "silence":
            // As the service does: a reply it lists, or an approval in the session, goes to silenced.
            let chat = body["chatID"]?.string.flatMap(UUID.init(uuidString:))
            if body["text"] != nil, service.ready?.contains(where: { $0.id == chat && $0.text == body["text"]?.string }) == true {
                service.ready?.removeAll { $0.id == chat }
            } else if let index = service.needsYou.firstIndex(where: { $0.id == id && $0.chatID == chat }) {
                service.silenced = (service.silenced ?? []) + [service.needsYou.remove(at: index)]
            } else if let session = model.sessions.first(where: { $0.id == chat }), let item = session.pendingRequests.first(where: { $0.id == id }) {
                service.silenced = (service.silenced ?? []) + [.init(id: item.id, chatID: session.id, title: session.title, place: nil, kind: "approval", text: item.text)]
            }
            service.revision += 1
            return try JSON.value(service)
        case "start":
            service.incoming.removeAll { $0.id == id }; service.revision += 1
            // Continuing answers with that session; a new one with the started session.
            let chat = body["continueChat"]?.string ?? startedID.uuidString
            return ["revision": 1, "summary": ["id": .string(chat), "title": "Fix the iPad sidebar badge"], "settings": "Claude", "items": [], "earlierCount": 0]
        case "threads":
            return try JSON.value(id == badge.id ? [sameWork, similar] : [Companion.DeskThread]())
        case "options":
            return try JSON.value(options((try? body["picks"]?.decode(Companion.SettingsRequest.self)) ?? .init()))
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
    check(sections.incoming.map(\.id) == [resultsEmail.id, badge.id, order.id], "To do: the service's requests")
    check(sections.ready.map(\.id) == [proofs.id, lid.id], "Ready: the service's, less one working or archived here since (\(sections.ready.map(\.title)))")
    check(sections.done.map(\.id) == [flyers.id], "Done: the service's, less one unarchived here since")
    check(sections.working.first { $0.id == ribbons.id }?.activity == "Working\u{2026}", "Working says what it's doing")
    check(sections.summary == "4 need you · 3 to do · 2 working · 2 ready", "header: \(sections.summary)")
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
    let keys = DeskSections.Section.allCases.map(\.key)

    // Home opens on the Desk when it's chosen; the Desk is the column's first entry.
    model.showDesk()
    check(model.showingHome && model.showingDesk && StudioSelection.saved == .desk, "Go > Desk opens Home on the Desk")
    // Wide enough for the whole board: five columns side by side, each with its cards.
    try await render(AnyView(ContentView()), 2200, 1000, "desk-board")
    let columns = keys.compactMap { frame("section:" + $0) }
    check(columns.count == 5, "the board renders five columns (\(columns.count))")
    check(zip(columns, columns.dropFirst()).allSatisfy { $0.maxX < $1.minX && abs($0.minY - $1.minY) < 1 }, "side by side, left to right: To do, Working, Needs you, Ready, Done")
    check(columns.allSatisfy { abs($0.width - DeskView.columnWidth) < 1 } && columns.allSatisfy { $0.height > 600 }, "each a fixed width, the page's height (\(columns.map(\.size)))")
    check(keys.allSatisfy { frame("count:" + $0) != nil } && keys.allSatisfy { frame("empty:" + $0) == nil }, "each with its count, none empty")
    func inside(_ card: String, _ column: String) -> Bool {
        guard let card = frame(card), let column = frame("section:" + column) else { return false }
        return card.minX >= column.minX - 0.5 && card.maxX <= column.maxX + 0.5
    }
    check(inside("request:\(badge.id)", "todo") && inside("working:\(sdhq.id)", "working") && inside("needs:\(approvalID)", "needsYou")
          && inside("ready:\(proofs.id)", "ready") && inside("done:\(flyers.id)", "done"), "each card in its column")
    check(["ignore:\(badge.id)", "approve:\(approvalID)", "open:\(approvalID)", "silence:\(approvalID)", "complete:\(proofs.id)", "readySilence:\(proofs.id)", "reopen:\(flyers.id)"]
            .allSatisfy { key in frame(key).map { button in columns.contains { $0.minX <= button.minX && button.maxX <= $0.maxX } } ?? false },
          "every card's buttons stay inside its column")
    if let deskEntry = MacHomeDebug.entries["desk"], let pinned = MacHomeDebug.entries["pinned"] {
        check(deskEntry.maxY <= pinned.minY && deskEntry.maxX <= MacHomeDebug.column.maxX + 1, "Desk is the first entry in Home's left column")
    } else { check(false, "Desk and Pinned entries in Home's column") }
    check(frame("chip:\(order.id)") != nil && frame("change:\(order.id)") == nil, "no place: Choose a place, no Change place")
    check(frame("change:\(badge.id)") != nil && frame("approve:\(approvalID)") != nil && frame("open:\(magnets.items[0].id)") != nil, "Change place, Approve and Open are there")
    check(needs.allSatisfy { frame("silence:\($0.id)") != nil }, "every Needs you card has Silence")
    check(frame("subtitle:\(plan.items[0].id)") != nil && frame("subtitle:\(approvalID)") == nil, "a project's session shows its own title under the project's")
    check(panel.title == "Desk", "window title on the Desk (\(panel.title))")
    let rightmost = DeskDebug.frames.values.map(\.maxX).max() ?? 0
    check(rightmost <= 2200 + 1, "nothing clips on the right (\(rightmost))")
    try await render(AnyView(DeskView().background(Color(nsColor: .windowBackgroundColor))), 1740, 900, "desk-light", dark: false)
    // Narrower: the board scrolls sideways, shown at Needs you.
    try await render(AnyView(ContentView()), 1200, 900, "desk-home-narrow")
    if let needsColumn = frame("section:needsYou"), let todo = frame("section:todo") {
        check(needsColumn.minX >= 0 && needsColumn.maxX <= 1200 + 1 && todo.minX < needsColumn.minX, "a narrow window scrolls the board to Needs you (\(needsColumn.minX)...\(needsColumn.maxX))")
    } else { check(false, "columns in the narrow window") }


    // Change place: every place with what belongs there, and a loose session last.
    try await render(AnyView(DeskPlacePicker(request: badge, desk: desk) {}.background(Color(nsColor: .windowBackgroundColor))), 380, 470, "desk-places")
    check(desk.places.count == places.count && desk.placeOptions.last?.kind == "loose", "places loaded from the service, loose last")
    check(sent.contains { $0["action"]?.string == "places" }, "asked the service for places")

    // MARK: Actions.
    // Open a question: selects its session and leaves Home.
    model.showDesk()
    try await render(AnyView(ContentView()), 2200, 1000, "desk-before-actions")
    try await click("open:\(magnets.items[0].id)")
    check(model.selectedID == magnets.id && !model.showingHome, "Open selects the session")

    // Approve: the session's own resolveApproval (no Claude process here, so it expires).
    model.showDesk()
    try await render(AnyView(ContentView()), 2200, 1000, "desk-approve")
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

    // Mark complete: {action: complete, chatID}; from Ready to Done. Reopen: {action: reopen, chatID}.
    try await click("complete:\(proofs.id)")
    check(sent.last == ["action": "complete", "chatID": .string(proofs.id.uuidString)], "Mark complete sends complete with the session (\(String(describing: sent.last)))")
    let afterComplete = desk.sections(in: model)
    check(!afterComplete.ready.contains { $0.id == proofs.id } && afterComplete.done.first?.id == proofs.id && proofs.record.archivedAt != nil,
          "a completed session moves from Ready to Done")
    try await Task.sleep(for: .milliseconds(300))
    try snapshot("desk-completed")
    try await click("reopen:\(proofs.id)")
    check(sent.last == ["action": "reopen", "chatID": .string(proofs.id.uuidString)], "Reopen sends reopen with the session")
    check(!desk.sections(in: model).done.contains { $0.id == proofs.id } && proofs.record.archivedAt == nil, "a reopened session leaves Done")
    // Silence a ready session: its id and what it said; off Ready until something new happens.
    try await click("readySilence:\(lid.id)")
    check(sent.last == ["action": "silence", "chatID": .string(lid.id.uuidString), "id": .string(lid.id.uuidString),
                        "text": "The 5 mm magnets fit the current lid with room to spare."], "a ready session's Silence sends its id and text")
    check(!desk.sections(in: model).ready.contains { $0.id == lid.id } && lid.record.archivedAt == nil, "silenced, it leaves Ready (not archived)")
    // An older service: Mark complete says so, and the rest of the Desk still works.
    let older = DeskModel(snapshot: service, transport: { body, _ in
        if body["action"]?.string == "complete" { throw RuntimeFailure("unsupported_operation") }
        return try JSON.value(service)
    })
    await older.complete(.init(id: lid.id, title: "PlayCase lid fit", place: nil, text: "x", finishedAt: now))
    check(older.problem?.contains("restarts") == true && !older.unsupported, "an older service: Mark complete waits for a restart, the Desk keeps working")

    // Change place, then Start there: its step loads the place's sessions like the work and a
    // new session's options, with the place chosen.
    let geekify = places[2]
    desk.choose(geekify, for: badge)
    try await Task.sleep(for: .milliseconds(300))
    try snapshot("desk-changed-place")
    let selectedBefore = model.selectedID
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(600))
        var started = record("Fix the iPad sidebar badge"); started.id = startedID
        _ = model.insertSession(started)
    }
    let step = DeskStartStep(request: badge, desk: desk)
    try await render(AnyView(DeskStartPopover(step: step) {}.background(Color(nsColor: .windowBackgroundColor))), 400, 400, "desk-start-continue")
    let asked = sent.last { $0["action"]?.string == "threads" }
    check(asked?["id"]?.string == badge.id.uuidString && (try? asked?["place"]?.decode(Companion.DeskPlace.self)) == geekify, "the step asks for threads in the place chosen")
    check((try? sent.last { $0["action"]?.string == "options" }?["place"]?.decode(Companion.DeskPlace.self)) == geekify, "and a new session's options there")
    check(frame("thread:\(sameWork.id)") != nil && frame("thread:\(similar.id)") != nil && frame("thread:new") != nil, "Continue in each session like the work, and New session")
    check(step.continuing == sameWork.id && frame("startModel") == nil, "a clear match is chosen; continuing needs no model")
    if let a = frame("thread:\(sameWork.id)"), let b = frame("thread:new") { check(a.maxY <= b.minY, "Continue in comes before New session") }
    try await click("thread:new")
    check(step.continuing == nil && frame("startProvider") != nil && frame("startModel") != nil, "New session: the agent and its model")
    try snapshot("desk-start-new")
    try await click("thread:\(sameWork.id)")
    try await click("startConfirm")
    for _ in 0..<20 where desk.startedNote == nil { try await Task.sleep(for: .milliseconds(100)) }
    let start = sent.last { $0["action"]?.string == "start" }
    check(start?["id"]?.string == badge.id.uuidString && (try? start?["place"]?.decode(Companion.DeskPlace.self)) == geekify
          && start?["continueChat"]?.string == sameWork.id.uuidString && start?["model"] == nil,
          "Continue sends start with the id, the place and the session to continue (\(String(describing: start)))")
    try await Task.sleep(for: .milliseconds(900))
    check(desk.startedNote?.chat == sameWork.id && desk.startedNote?.continued == true && desk.startedNote?.name == "Mac Desk page" && model.selectedID == selectedBefore,
          "it runs in the background: a note says where, and nothing opens")
    check(!desk.sections(in: model).incoming.contains { $0.id == badge.id }, "a started request leaves the Desk")
    try await render(AnyView(DeskView().background(Color(nsColor: .windowBackgroundColor))), 1080, 700, "desk-started-note")
    check(frame("startedNote") != nil, "the Desk shows the note, with Open")
    // A new session with the model picked: agent and model go with start.
    let modelStep = DeskStartStep(request: resultsEmail, desk: desk)
    try await render(AnyView(DeskStartPopover(step: modelStep) {}.background(Color(nsColor: .windowBackgroundColor))), 400, 300, "desk-start-model")
    check(modelStep.threads?.isEmpty == true && frame("thread:new") == nil && frame("startModel") != nil, "nothing like it already there: just the model")
    await modelStep.pick(modelStep.change(picking: "gpt-6.1-sol", of: "codex"))
    check(modelStep.options?.backend == "codex" && modelStep.options?.model == "gpt-6.1-sol", "picking another agent's model switches to it")
    try await Task.sleep(for: .milliseconds(300))
    try snapshot("desk-start-model-picked")
    try await click("startConfirm")
    for _ in 0..<20 where desk.startedNote?.chat != startedID { try await Task.sleep(for: .milliseconds(100)) }
    let modelStart = sent.last { $0["action"]?.string == "start" }
    check(modelStart?["id"]?.string == resultsEmail.id.uuidString && modelStart?["agent"]?.string == "codex" && modelStart?["model"]?.string == "gpt-6.1-sol"
          && modelStart?["continueChat"] == nil, "Start sends the agent and model picked (\(String(describing: modelStart)))")
    check(desk.startedNote?.chat == startedID && desk.startedNote?.continued == false && desk.startedNote?.name == "USA Archery" && model.selectedID == selectedBefore,
          "a new session starts in the background too")
    // Nothing changed: start sends no model, so it starts as a new session there would.
    service.incoming.append(order)
    desk.load(service)
    desk.choose(usaPlace, for: order)
    let plain = DeskStartStep(request: order, desk: desk)
    await plain.load()
    await plain.start()
    let plainStart = sent.last { $0["action"]?.string == "start" }
    check(plainStart?["id"]?.string == order.id.uuidString && plainStart?["agent"] == nil && plainStart?["model"] == nil, "untouched, start sends just the place")

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

    // MARK: Empty columns: nothing waits on you or to be placed; Working still shows its cards.
    for session in model.sessions {
        let pending = Set(session.pendingRequests.map(\.id))
        for index in session.record.items.indices where pending.contains(session.record.items[index].id) {
            session.record.items[index].approvalState = .denied
        }
    }
    service.needsYou = []; service.incoming = []; service.ready = []; service.done = []; service.revision = 50
    desk.load(service)
    model.showDesk()
    try await render(AnyView(ContentView()), 2200, 1000, "desk-calm-working")
    check(frame("empty:needsYou") != nil && frame("empty:todo") != nil && frame("empty:ready") != nil && frame("empty:done") != nil
          && frame("empty:working") == nil && frame("working:\(sdhq.id)") != nil, "empty columns say so in a line; Working shows its cards")
    check(desk.sections(in: model).summary == "3 working", "header: 3 working, the plan's session too once answered (\(desk.sections(in: model).summary))")
    ribbons.isRunning = false; sdhq.isRunning = false; plan.isRunning = false
    try await render(AnyView(ContentView()), 2200, 1000, "desk-empty")
    check(keys.allSatisfy { frame("empty:" + $0) != nil } && desk.sections(in: model).summary == "All clear", "nothing at all: every column empty, All clear")

    // Home's other pages are unchanged: Pinned still opens with its own title.
    UserDefaults.standard.set("pinned", forKey: "macStudioSelection")
    try await render(AnyView(ContentView()), 1500, 950, "studios-pinned-after-desk")
    check(!model.showingDesk && frame("section:needsYou") == nil && panel.title == "Studios", "Pinned shows the Studios page again (\(panel.title))")
    StudioSelection.save(.desk)
    model.showStudiosOverview()
    check(StudioSelection.saved == .pinned && model.showingHome && !model.showingDesk, "Command Center's Studios opens the Studios page, not the Desk")

    panel.orderOut(nil)
    print(failures == 0 ? "PASS: the Desk — the board: five columns, counts and empty lines, local Needs you and Working, service To do, replies, Ready and Done, Open/Approve/Ignore/Silence/Mark complete/Reopen/Start there/Add, desk.changed, older service. Proof: \(root.path)"
                        : "FAIL: \(failures) checks failed. Renders: \(root.path)")
}
Task { @MainActor in
    do { try await run(); exit(failures == 0 ? 0 : 1) } catch { print("FAIL: \(error)"); exit(1) }
}
app.run()
