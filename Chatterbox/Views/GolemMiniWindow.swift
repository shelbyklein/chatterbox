import AppKit
import Observation
import SwiftUI

/// One native panel for the existing assistant. It never owns an agent or a transcript.
@MainActor
@Observable
final class GolemMiniWindow: NSObject, NSWindowDelegate {
    static let visibleKey = "golemMiniVisible"
    static let expandedFrameKey = "golemMiniExpandedFrame"
    static let avatarFrameKey = "golemMiniAvatarFrame"
    static let collapsedKey = "dotCollapsed"
    private(set) var collapsed: Bool
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private(set) var panel: GolemPanel?
    @ObservationIgnored private var expandedSize = NSSize(width: 400, height: 420)
    @ObservationIgnored private var positioning = false
    @ObservationIgnored private var screenObserver: NSObjectProtocol?

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        collapsed = defaults.bool(forKey: Self.collapsedKey)
        super.init()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepOnScreen() }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    var isReading: Bool { panel?.isVisible == true && panel?.isKeyWindow == true && !collapsed }

    func show() {
        guard let model else { return }
        let dot = model.ensureDot()
        if panel == nil {
            let panel = GolemPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.delegate = self
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.animationBehavior = .none
            panel.becomesKeyOnlyIfNeeded = true
            panel.title = dot.title
            let host = NSHostingView(rootView: GolemMiniContent(session: dot, controller: self).environment(model))
            // Keep window clipping in AppKit, including any WebKit preview layers.
            host.wantsLayer = true
            host.layer?.cornerRadius = 14
            host.layer?.masksToBounds = true
            host.sizingOptions = []
            panel.contentView = host
            self.panel = panel
            if let saved = savedFrame(Self.expandedFrameKey) { expandedSize = saved.size }
            let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let size = collapsed ? NSSize(width: 96, height: 96) : expandedSize
            let fallback = NSRect(x: area.maxX - size.width - 24, y: area.minY + 24, width: size.width, height: size.height)
            configure(frame: savedFrame(collapsed ? Self.avatarFrameKey : Self.expandedFrameKey) ?? fallback)
        }
        keepOnScreen()
        if collapsed { panel?.orderFrontRegardless() }
        else { panel?.makeKeyAndOrderFront(nil) }
        if isReading { Attention.shared.markSeen(dot.id) }
    }

    func hide() {
        rememberFrame()
        panel?.orderOut(nil)
        // Release hosted chat/media views while hidden. Drafts belong to the session.
        panel?.contentView = nil
        panel = nil
    }

    func setCollapsed(_ value: Bool) {
        guard value != collapsed, let panel else { return }
        let anchor = NSPoint(x: panel.frame.maxX, y: panel.frame.minY)
        if !collapsed { expandedSize = panel.frame.size }
        rememberFrame()
        collapsed = value
        defaults.set(value, forKey: Self.collapsedKey)
        let size = value ? NSSize(width: 96, height: 96) : expandedSize
        configure(frame: NSRect(x: anchor.x - size.width, y: anchor.y, width: size.width, height: size.height))
        if value { panel.resignKey(); panel.orderFrontRegardless() }
        else { panel.makeKeyAndOrderFront(nil) }
        if isReading, let dot = model?.dot { Attention.shared.markSeen(dot.id) }
    }

    func closeMini() { model?.showingDot = false }

    func openFullChat() {
        guard let model else { return }
        model.openDot()
        model.showingSettings = false
        model.webPage = nil
        revealMainWindow()
    }

    /// Follow-up links from the mini must also reveal the main window, even in another app.
    func revealMainWindow() {
        guard let model else { return }
        if let window = model.mainChatWindow, window.isVisible || window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            model.revealMainChatWindow?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configure(frame: NSRect) {
        guard let panel else { return }
        positioning = true
        panel.acceptsTyping = !collapsed
        panel.hasShadow = false
        if collapsed { panel.styleMask.remove(.resizable) } else { panel.styleMask.insert(.resizable) }
        panel.minSize = collapsed ? NSSize(width: 96, height: 96) : NSSize(width: 320, height: 360)
        panel.maxSize = collapsed ? NSSize(width: 96, height: 96) : NSSize(width: 520, height: 440)
        var fitted = frame
        fitted.size.width = min(max(fitted.width, panel.minSize.width), panel.maxSize.width)
        fitted.size.height = min(max(fitted.height, panel.minSize.height), panel.maxSize.height)
        panel.setFrame(Self.clamped(fitted, to: NSScreen.screens.map(\.visibleFrame)), display: true)
        positioning = false
        rememberFrame()
    }

    func keepOnScreen() {
        guard let panel else { return }
        panel.setFrame(Self.clamped(panel.frame, to: NSScreen.screens.map(\.visibleFrame)), display: true)
        rememberFrame()
    }

    /// Restore onto an attached display, even when the previous display was unplugged.
    static func clamped(_ frame: NSRect, to screens: [NSRect]) -> NSRect {
        guard let screen = screens.max(by: { a, b in
            let x = a.intersection(frame), y = b.intersection(frame)
            return (x.isNull ? 0 : x.width * x.height) < (y.isNull ? 0 : y.width * y.height)
        }) else { return frame }
        let size = NSSize(width: min(frame.width, screen.width), height: min(frame.height, screen.height))
        return NSRect(x: min(max(frame.minX, screen.minX), screen.maxX - size.width),
                      y: min(max(frame.minY, screen.minY), screen.maxY - size.height), width: size.width, height: size.height)
    }

    private func savedFrame(_ key: String) -> NSRect? {
        guard let string = defaults.string(forKey: key) else { return nil }
        let frame = NSRectFromString(string)
        guard frame.width.isFinite, frame.height.isFinite, frame.minX.isFinite, frame.minY.isFinite,
              frame.width >= 96, frame.height >= 96 else { return nil }
        return frame
    }

    private func rememberFrame() {
        guard !positioning, let panel else { return }
        defaults.set(NSStringFromRect(panel.frame), forKey: collapsed ? Self.avatarFrameKey : Self.expandedFrameKey)
        if !collapsed { expandedSize = panel.frame.size }
    }

    func windowDidMove(_ notification: Notification) { rememberFrame() }
    func windowDidResize(_ notification: Notification) { rememberFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { keepOnScreen() }
    func windowDidBecomeKey(_ notification: Notification) {
        if !collapsed, let dot = model?.dot { Attention.shared.markSeen(dot.id) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { closeMini(); return false }
}

final class GolemPanel: NSPanel {
    var acceptsTyping = true
    override var canBecomeKey: Bool { acceptsTyping }
    override var canBecomeMain: Bool { false }
}

private struct GolemMiniContent: View {
    let session: ChatSession
    let controller: GolemMiniWindow
    @AppStorage(Theme.backgroundKey) private var background = "standard"
    @AppStorage(Theme.schemeKey) private var scheme = "system"
    @AppStorage(Theme.highlightKey) private var highlight = "default"

    var body: some View {
        Group {
            if controller.collapsed {
                avatar
            } else {
                GolemMiniConversation(session: session, controller: controller)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(Theme.colorScheme(background: background, scheme: scheme))
        .tint(highlight == "default" ? nil : Color.highlight)
        .onChange(of: session.title) { _, title in controller.panel?.title = title }
    }

    private var avatar: some View {
        let unread = Attention.shared.dotUnreadCount(session)
        return GolemAnimated(mood: GolemAvatar.mood(of: session))
            .padding(6)
            .background(Circle().fill(session.isWaitingOnYou ? Color.yellow.opacity(0.18) : .clear).padding(10))
            .overlay(alignment: .topTrailing) {
                if unread > 0 {
                    Text("\(unread)").font(.caption2.weight(.bold))
                        .foregroundStyle(Color.onHighlight)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.highlight)).padding(8)
                }
            }
            .overlay {
                MiniDragRegion(onClick: { controller.setCollapsed(false) }, onDragEnd: controller.keepOnScreen,
                               onOpenFull: controller.openFullChat, onHide: controller.closeMini)
            }
            .help("Open \(session.title). Drag to move; right-click for more.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(session.title) mini\(unread > 0 ? ", \(unread) unread" : "")")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { controller.setCollapsed(false) }
    }
}

/// A purpose-built companion: one bounded update, the character, and one input bar.
/// Full transcript rendering belongs to the main chat, never this narrow panel.
private struct GolemMiniConversation: View {
    let session: ChatSession
    let controller: GolemMiniWindow
    @State private var draft: String
    @State private var attachments: [Attachment]
    @State private var attachmentError: String?
    @State private var showingModels = false
    @FocusState private var focused: Bool

    init(session: ChatSession, controller: GolemMiniWindow) {
        self.session = session
        self.controller = controller
        _draft = State(initialValue: session.draft)
        _attachments = State(initialValue: session.draftAttachments)
    }

    private var latestReply: DisplayItem? {
        session.items.last { $0.kind == .assistant && $0.phase != .commentary && !$0.text.isEmpty }
    }
    private var updateText: String? {
        if session.isWaitingOnYou { return session.lastActionSummary }
        if session.isRunning {
            let notes = session.items.filter { session.liveCommentaryIDs.contains($0.id) }.suffix(2)
            return notes.isEmpty ? (session.lastActionSummary ?? "Thinking…") : notes.map(\.text).joined(separator: "\n\n")
        }
        return latestReply?.text
    }
    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                if let text = updateText {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(session.isWaitingOnYou ? "Needs you" : session.isRunning ? "Working" : session.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(session.isWaitingOnYou ? Color.yellow : .secondary)
                            Spacer()
                            Button(action: controller.openFullChat) {
                                Label(session.isWaitingOnYou ? "Answer in chat" : "Open chat", systemImage: "arrow.up.right")
                                    .font(.system(size: 11))
                            }.buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        ScrollView {
                            Text(MessageClipboard.plain(String(text.prefix(8_000))))
                                .font(.system(size: 14))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxHeight: max(48, min(140, geometry.size.height - 248)))
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color(nsColor: .windowBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.12)))
                }
                GolemAnimated(mood: GolemAvatar.mood(of: session))
                    .frame(width: 124, height: 124)
                    .overlay {
                        MiniDragRegion(onDragEnd: controller.keepOnScreen,
                                       onOpenFull: controller.openFullChat, onHide: controller.closeMini)
                    }
                    .help("Drag to move \(session.title)")
                if !attachments.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(attachments) { file in
                                Button { attachments.removeAll { $0.id == file.id } } label: {
                                    Label(file.name, systemImage: "xmark.circle.fill").lineLimit(1)
                                }.buttonStyle(.plain).help("Remove \(file.name)")
                            }
                        }.font(.caption).padding(8)
                    }
                    .frame(height: 30)
                    .background(.regularMaterial, in: Capsule())
                }
                if let attachmentError { Text(attachmentError).font(.caption).foregroundStyle(.orange).lineLimit(2) }
                composer
            }
            .frame(width: max(0, geometry.size.width - 24), height: max(0, geometry.size.height - 24), alignment: .bottom)
            .padding(12)
        }
        .onChange(of: draft) { _, value in session.draft = value }
        .onChange(of: attachments) { _, value in session.draftAttachments = value }
        .onChange(of: latestReply?.id) {
            if controller.isReading { Attention.shared.markSeen(session.id) }
        }
        .onChange(of: ChatCommands.shared.modelPopoverRequests) {
            if showingModels || controller.panel?.isKeyWindow == true { showingModels.toggle() }
        }
        .popover(isPresented: $showingModels) {
            ModelPopover(session: session) { showingModels = false }
                .task {
                    await ClaudeModels.shared.refresh()
                    if CodexAppServer.shared.models.isEmpty { try? await CodexAppServer.shared.refreshModels() }
                }
        }
        .onKeyPress(.escape) {
            guard session.isRunning else { return .ignored }
            session.interrupt(); return .handled
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button("Attach Files…", action: chooseFiles)
                Button("Paste Image") {
                    if let files = Attachments.fromPasteboard() { attachments += files }
                }
                Divider()
                Button("Model and Effort…") { showingModels = true }
                Button("Open Full Chat", action: controller.openFullChat)
                Button("Hide Mini", action: controller.closeMini)
            } label: {
                Image(systemName: "plus").font(.system(size: 17)).frame(width: 28, height: 30)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("More options")
            TextField("Message \(session.title)", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...4)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .focused($focused).accessibilityLabel("Message")
                .onSubmit { send() }
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
                        return .handled
                    }
                    if press.modifiers.contains(.command) { send(now: true); return .handled }
                    return .ignored
                }
            if session.isRunning && !canSend {
                Button { session.interrupt() } label: { Image(systemName: "stop.fill").frame(width: 30, height: 30) }
                    .buttonStyle(.plain).accessibilityLabel("Stop").help("Stop (Esc)")
            } else {
                Button { send() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(canSend ? Color.onHighlight : Color.secondary)
                        .background(Circle().fill(canSend ? Color.highlight : Color.primary.opacity(0.06)))
                }.buttonStyle(.plain).disabled(!canSend).accessibilityLabel("Send")
            }
            Button { controller.setCollapsed(true) } label: {
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).frame(width: 24, height: 30)
            }.buttonStyle(.plain).foregroundStyle(.secondary).help("Minimize to avatar").accessibilityLabel("Minimize to avatar")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.primary.opacity(0.12)))
    }

    private func send(now: Bool = false) {
        guard canSend else { return }
        let text = draft, files = attachments
        draft = ""; attachments = []; session.draft = ""; session.draftAttachments = []
        if now { session.sendNow(text, attachments: files) } else { session.send(text, attachments: files) }
    }

    private func chooseFiles() {
        let picker = NSOpenPanel()
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        guard picker.runModal() == .OK else { return }
        do { attachments += try picker.urls.map(Attachments.importFile); attachmentError = nil }
        catch { attachmentError = error.localizedDescription }
    }
}

/// AppKit owns drag gestures, so selecting chat text cannot move the window and a drag
/// of the avatar never also expands it. A nonactivating panel accepts the first click.
struct MiniDragRegion: NSViewRepresentable {
    var onClick: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var onOpenFull: (() -> Void)?
    var onHide: (() -> Void)?

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
        view.onClick = onClick; view.onDragEnd = onDragEnd
        view.onOpenFull = onOpenFull; view.onHide = onHide
    }

    final class DragView: NSView {
        var onClick: (() -> Void)?
        var onDragEnd: (() -> Void)?
        var onOpenFull: (() -> Void)?
        var onHide: (() -> Void)?
        private var start: NSPoint?
        private var origin = NSPoint.zero
        private var dragged = false
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            start = window.convertPoint(toScreen: event.locationInWindow)
            origin = window.frame.origin; dragged = false
        }
        override func mouseDragged(with event: NSEvent) {
            guard let start, let window else { return }
            let point = window.convertPoint(toScreen: event.locationInWindow)
            let dx = point.x - start.x, dy = point.y - start.y
            if hypot(dx, dy) > 3 { dragged = true }
            if dragged { window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy)) }
        }
        override func mouseUp(with event: NSEvent) {
            guard start != nil else { return }
            start = nil
            if dragged { onDragEnd?() } else { onClick?() }
        }
        override func rightMouseDown(with event: NSEvent) {
            guard onClick != nil else { return }
            let menu = NSMenu()
            for (title, action) in [("Open Chat", #selector(openChat)), ("Open in Chatterbox", #selector(openFull)), ("Hide Mini", #selector(hideMini))] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self; menu.addItem(item)
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
        @objc private func openChat() { onClick?() }
        @objc private func openFull() { onOpenFull?() }
        @objc private func hideMini() { onHide?() }
    }
}

/// Find the hosting window for main-window activation and per-window keyboard handling.
struct ChatWindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> Reader { let view = Reader(); view.onWindow = onWindow; return view }
    func updateNSView(_ view: Reader, context: Context) { view.onWindow = onWindow }
    final class Reader: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { if let window { onWindow?(window) } }
    }
}
