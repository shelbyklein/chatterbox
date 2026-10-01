import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(AppModel.self) private var model
    /// The small chat floating over a page: fewer controls, tighter margins.
    @Environment(\.compactChat) private var compact
    let session: ChatSession
    /// The message box's text and attachments. Typing stays in this view; each change is
    /// copied to the chat (ChatSession.draft), so it's still there after looking at another
    /// chat. Binding the field to the chat itself redrew the whole chat on every keystroke,
    /// which garbled wrapped lines.
    @State private var draft: String
    @State private var attachments: [Attachment]

    init(session: ChatSession) {
        self.session = session
        _draft = State(initialValue: session.draft)
        _attachments = State(initialValue: session.draftAttachments)
    }
    @State private var attachError: String?
    @State private var isDropTargeted = false
    @State private var pasteMonitor: Any?
    @State private var projectConflict: ChatSession?
    @State private var reviewing: Attachment?
    @State private var commandIndex = 0
    /// The draft at which the user pressed Esc on the "/" menu, so it stays closed for that text.
    @State private var dismissedCommandDraft: String?
    private let commands = ChatCommands.shared
    /// The Issues panel on the right (see IssuesPanel.swift).
    @State private var issuesPanel = IssuesPanelState()
    @FocusState private var composerFocused: Bool
    private let appearance = ReaderStyleSettings()

    var body: some View {
        VStack(spacing: 0) {
            if session.record.archivedAt != nil { archivedBanner }
            if session.record.backend == .claude, let status = ClaudeModels.shared.statusMessage { claudeBanner(status) }
            if session.record.backend == .codex, let status = CodexAppServer.shared.statusMessage { codexBanner(status) }
            transcript
            composer
        }
        .navigationTitle(session.title)
        .toolbar { toolbarContent }
        // Agents often link files by bare path ("/Users/…/Print.pdf"), which macOS can't open as a URL.
        .environment(\.chatFolder, session.workingFolder)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == PathLinks.scheme {
                PathLinks.reveal(url)
                return .handled
            }
            guard let file = FileLink.resolve(url, in: session.workingFolder) else { return .systemAction }
            NSWorkspace.shared.open(file)
            return .handled
        })
        .inspector(isPresented: $issuesPanel.isOpen) { IssuesPanel(session: session, panel: issuesPanel) }
        // Re-read git when the chat opens, its folder changes, or a turn ends (the agent may have committed).
        .task(id: "\(session.record.projectFolder ?? "")|\(session.isRunning)") {
            guard let folder = session.record.projectFolder, !session.isRunning else { return }
            await GitStatusStore.shared.refresh(folder)
            session.updateGitHubRepo(from: GitStatusStore.shared.status(for: folder))
        }
        .task(id: session.record.backend == .codex ? session.record.codex?.folder : nil) {
            if session.record.backend == .codex, let folder = session.record.codex?.folder {
                await CodexAppServer.shared.refreshSkills(for: folder)
            }
        }
        .onAppear {
            composerFocused = true
            installPasteMonitor()
        }
        .onChange(of: draft) { _, text in session.draft = text }
        .onChange(of: attachments) { _, files in session.draftAttachments = files }
        .onDisappear {
            if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
            pasteMonitor = nil
        }
        .onDrop(of: [.fileURL, .image, .data], isTargeted: $isDropTargeted, perform: handleDrop)
        .sheet(item: $reviewing) { image in
            ImageReviewView(attachment: image) { text, files in session.send(text, attachments: files) }
        }
        .alert("That folder already has a chat", isPresented: Binding(get: { projectConflict != nil }, set: { if !$0 { projectConflict = nil } }), presenting: projectConflict) { owner in
            Button("Open That Chat") { model.selectedID = owner.id }
            Button("Cancel", role: .cancel) {}
        } message: { owner in
            Text("\u{201C}\(owner.title)\u{201D} is bound to \(owner.record.projectFolder ?? "it"). Each project folder has one chat, and you can switch models inside it.")
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.highlight, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(Color.highlight.opacity(0.06))
                    .overlay(Label("Drop to attach", systemImage: "paperclip").font(.title3).foregroundStyle(Color.highlight))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Attachments

    /// ⌘V with an image or copied files on the pasteboard attaches them instead of pasting text.
    private func installPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "v",
                  event.window?.isKeyWindow == true, composerFocused,
                  let pasted = Attachments.fromPasteboard() else { return event }
            add(pasted)
            return nil
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach"
        guard panel.runModal() == .OK else { return }
        add(panel.urls.compactMap(importOrReport))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in add([importOrReport(url)].compactMap { $0 }) }
                }
            } else if let type = Self.fileType(of: provider) {
                // A file dragged from an app without a Finder path (an .ai from a design app):
                // keep the file itself, under its own name, not a picture of it.
                let name = (provider.suggestedName ?? "Dropped file") + (type.preferredFilenameExtension.map { ".\($0)" } ?? "")
                _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                    guard let url else { return }
                    // The file is only there until this returns, so copy it now.
                    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try? FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
                    let file = copy.appendingPathComponent(name)
                    guard (try? FileManager.default.copyItem(at: url, to: file)) != nil else { return }
                    Task { @MainActor in
                        add([importOrReport(file)].compactMap { $0 })
                        try? FileManager.default.removeItem(at: copy)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        do { add([try Attachments.importImageData(data, name: provider.suggestedName ?? "Dropped image")]) } catch { attachError = error.localizedDescription }
                    }
                }
            }
        }
        return true
    }

    /// The most specific file type a drag offers, unless it's only a plain picture.
    private static func fileType(of provider: NSItemProvider) -> UTType? {
        provider.registeredTypeIdentifiers.lazy.compactMap(UTType.init).first { type in
            type.conforms(to: .data) && !Attachments.rasterTypes.contains(where: type.conforms(to:))
                && type != .data && type != .image
        }
    }

    private func importOrReport(_ url: URL) -> Attachment? {
        do { return try Attachments.importFile(url) } catch {
            attachError = error.localizedDescription
            return nil
        }
    }

    private func add(_ new: [Attachment]) {
        attachError = nil
        attachments += new
        composerFocused = true
    }

    private var attachmentTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        attachments.removeAll { $0.id == attachment.id }
                        Attachments.remove([attachment])
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if session.items.isEmpty {
                    EmptyChatView(session: session) { draft = $0; submit() }
                        .padding(.top, 60)
                } else {
                    let agents = session.agentsByItem
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleItems) { item in
                            Group {
                                if isWaitingOnYou(item) {
                                    waitingMarker(item)
                                } else {
                                    ItemView(item: item, isActive: session.isRunning && item.id == session.items.last?.id,
                                             agent: agents[item.id] ?? session.record.backend,
                                             onApproval: session.resolveApproval, onAnswer: session.answerQuestions,
                                             onSendNow: session.sendQueuedNow)
                                }
                            }
                            .padding(.vertical, rowPadding(item))
                            .id(item.id)
                        }
                        if session.isRunning && !isVisiblyWorking {
                            TypingIndicator()
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, compact ? 14 : 24)
                    .padding(.vertical, compact ? 12 : 20)
                    .frame(maxWidth: appearance.style.contentWidth)
                    .environment(\.readerStyle, appearance.style)
                    .environment(\.reviewImage, ImageReviewAction { reviewing = $0 })
                    .frame(maxWidth: .infinity)
                }
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: session.items.count) { scrollToBottom(proxy) }
            .onChange(of: session.items.last?.text) { scrollToBottom(proxy) }
        }
    }

    /// Rows to show: thinking can be hidden in Settings → Appearance.
    private var visibleItems: [DisplayItem] {
        appearance.showThinking ? session.items : session.items.filter { $0.kind != .thought }
    }

    /// Half the paragraph spacing above and below each row; step rows get less in compact mode.
    private func rowPadding(_ item: DisplayItem) -> CGFloat {
        let spacing = appearance.style.paragraphSpacing / 2
        let isStep = item.kind == .tool || item.kind == .thought || item.kind == .notice
            || (item.kind == .assistant && item.phase == .commentary)
        return isStep && appearance.compactSteps ? 1 : spacing
    }

    /// True when the last row already shows activity, so the typing dots would be redundant.
    private var isVisiblyWorking: Bool {
        guard let last = visibleItems.last else { return false }
        switch last.kind {
        case .assistant: return last.phase == .streaming
        case .tool: return last.toolState == .running
        case .thought: return true
        case .questions, .approval: return last.approvalState == .pending
        default: return false
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    // MARK: - Composer

    // MARK: - Waiting on you

    /// Approvals and questions waiting for an answer. They're shown above the message box, not
    /// in the transcript: the transcript is a lazy list, and when rows near the bottom change
    /// height it keeps stale click positions until you scroll, so card buttons missed.
    private func isWaitingOnYou(_ item: DisplayItem) -> Bool {
        (item.kind == .approval || item.kind == .questions) && item.approvalState == .pending
    }

    /// The earliest waiting card; the rest follow once it's answered.
    private var waitingCard: DisplayItem? { session.items.first(where: isWaitingOnYou) }

    private func waitingMarker(_ item: DisplayItem) -> some View {
        Label(item.kind == .questions ? "Waiting for your answer below" : "Waiting for your approval below",
              systemImage: "arrow.down.circle")
            .font(.callout)
            .foregroundStyle(Color.highlight)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var waitingTray: some View {
        // Hidden copies of the paperclip and send/stop buttons, so the card lines up exactly
        // with the text field below it.
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "paperclip").font(.system(size: 17)).hidden()
            ScrollView {
                if let item = waitingCard {
                    ItemView(item: item, agent: session.record.backend,
                             onApproval: session.resolveApproval, onAnswer: session.answerQuestions)
                        .environment(\.cardFillsWidth, true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(item.id)
                }
            }
            // Tall cards (a long plan) scroll inside the tray instead of pushing the chat away.
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            if session.isRunning {
                Image(systemName: "stop.circle.fill").font(.system(size: 26)).hidden()
            }
            Image(systemName: "arrow.up.circle.fill").font(.system(size: 26)).hidden()
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.hasBackgroundWork {
                BackgroundWorkBar(session: session, color: appearance.style.color(for: session.record.backend))
                    .padding(.leading, 34)
            }
            if waitingCard != nil { waitingTray }
            if !commandMatches.isEmpty { commandMenu }
            if draft.hasPrefix("!") {
                Label("Runs in your shell in \((session.workingFolder as NSString).abbreviatingWithTildeInPath). The output goes to \(session.record.backend.label) with your next message.",
                      systemImage: "terminal")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 34)
            }
            if !attachments.isEmpty { attachmentTray }
            if let attachError {
                Label(attachError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            composerRow
            modelStatus
        }
        .padding(.horizontal, compact ? 12 : 20)
        .padding(.vertical, compact ? 10 : 12)
        .frame(maxWidth: appearance.style.contentWidth + 40)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: - Slash commands

    /// Claude Code's commands and skills (including the project's), or Codex's skills.
    private var availableCommands: [SlashCommand] {
        if session.record.backend == .codex {
            return session.record.codex.map { CodexAppServer.shared.skills[$0.folder] ?? [] } ?? []
        }
        return session.claudeCommands ?? ClaudeModels.shared.commands
    }

    /// Shown while the draft is "/" plus a partial command name.
    private var commandMatches: [SlashCommand] {
        guard draft.hasPrefix("/"), !draft.contains(where: \.isWhitespace), draft != dismissedCommandDraft else { return [] }
        return Array(SlashCommand.matches(String(draft.dropFirst()), in: availableCommands).prefix(8))
    }

    private var commandMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(commandMatches.enumerated()), id: \.element.id) { index, command in
                Button { complete(command) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("/" + command.name).font(.callout.weight(.semibold)).lineLimit(1)
                        if let hint = command.argumentHint {
                            Text(hint).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        Text(command.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(index == commandIndex ? Color.highlight.opacity(0.18) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .padding(.leading, 34)
    }

    private func moveCommandSelection(_ offset: Int) -> KeyPress.Result {
        let count = commandMatches.count
        guard count > 0 else { return .ignored }
        commandIndex = (commandIndex + offset + count) % count
        return .handled
    }

    private func completeCommand() -> KeyPress.Result {
        let matches = commandMatches
        guard !matches.isEmpty else { return .ignored }
        complete(matches[min(commandIndex, matches.count - 1)])
        return .handled
    }

    private func complete(_ command: SlashCommand) {
        draft = "/\(command.name) "
        composerFocused = true
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button(action: chooseFiles) {
                Image(systemName: "paperclip").font(.system(size: 17))
                    .frame(height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Attach files or images. You can also paste or drag them in.")
            .accessibilityLabel("Attach Files")

            TextField(session.isRunning ? "Add something while it works\u{2026}" : "Message \(session.record.backend.label)", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .accessibilityLabel("Message")
                .lineLimit(1...8)
                .focused($composerFocused)
                .onSubmit(submit)
                .onKeyPress(.upArrow) { moveCommandSelection(-1) }
                .onKeyPress(.downArrow) { moveCommandSelection(1) }
                .onKeyPress(.tab) { completeCommand() }
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.command), session.isRunning {
                        submit(now: true)
                        return .handled
                    }
                    // Shift-Return starts a new line at the cursor, like Option-Return.
                    if press.modifiers.contains(.shift) {
                        NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
                        return .handled
                    }
                    return completeCommand()
                }
                .onKeyPress(.escape) {
                    guard !commandMatches.isEmpty else { return .ignored }
                    dismissedCommandDraft = draft
                    return .handled
                }
                .onChange(of: draft) { commandIndex = 0 }
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(appearance.style.color(for: session.record.backend).opacity(composerFocused ? 0.8 : 0.45),
                                  lineWidth: composerFocused ? 1.5 : 1))
                .animation(.easeOut(duration: 0.15), value: session.record.backend)

            if session.isRunning, let started = session.record.turnStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(ChatSession.durationText(max(0, Int(context.date.timeIntervalSince(started)))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(height: 36)
                .help("Working since \(started.formatted(date: .omitted, time: .shortened))")
            }
            if session.isRunning {
                Button(action: session.interrupt) {
                    Image(systemName: "stop.circle.fill").font(.system(size: 26))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(".", modifiers: .command)
                .help("Stop (Esc or \u{2318}.)")
                .accessibilityLabel("Stop")
                // Esc stops the reply from anywhere in the chat. While the "/" menu is open,
                // Esc closes the menu instead. Kept in the background so it takes no room in the row.
                .background {
                    if commandMatches.isEmpty {
                        Button("Stop", action: session.interrupt)
                            .keyboardShortcut(.escape, modifiers: [])
                            .opacity(0)
                            .accessibilityHidden(true)
                    }
                }
            }

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 26))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSend ? Color.primary : Color.secondary)
            .disabled(!canSend)
            // Named for VoiceOver and for assistants that work the Mac through Accessibility,
            // which otherwise only see an unnamed arrow icon.
            .accessibilityLabel("Send")
            .help(session.isRunning ? "Add to the current reply (\u{21A9}), or \u{2318}\u{21A9} to stop and send now" : "Send")
        }
    }

    private func submit() { submit(now: false) }

    /// `now`: ⌘↩ while the agent works stops it and sends this message right away.
    private func submit(now: Bool) {
        guard canSend else { return }
        let text = draft
        let files = attachments
        draft = ""
        attachments = []
        attachError = nil
        if now { session.sendNow(text, attachments: files) } else { session.send(text, attachments: files) }
    }

    private var archivedBanner: some View {
        HStack {
            Image(systemName: "archivebox")
            Text("This chat is archived. Sending a message brings it back.")
            Spacer()
            Button("Unarchive") { model.unarchive(session) }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
    }

    private func claudeBanner(_ status: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(status).lineLimit(2)
            Spacer()
            Button("Retry") { Task { await ClaudeModels.shared.refresh(force: true) } }
            Button("Open Settings") { model.showingSettings = true }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            ToneMenu(session: session)

            if let studio = model.studio(for: session) { studioButton(studio) } else { projectButton }
            if let status = GitStatusStore.shared.status(for: session.record.projectFolder),
               let remote = status.remote(preferring: session.record.gitRemote), let repo = remote.repo {
                RepoChip(repo: repo, remote: remote, status: status, folder: session.record.projectFolder ?? "",
                         onSelectRemote: session.setGitRemote, onShowIssues: { issuesPanel.show() })
                IssueToolbarItems(session: session, panel: issuesPanel, repo: repo, branch: status.branch)
            }

            if session.isDot {
                Button { model.showingDotComputer.toggle() } label: {
                    ToolbarLabel("Computer", systemImage: "desktopcomputer")
                }
                .help("Dot's own computer: a browser it uses for web work, which you can watch and take over")
            }
            if session.record.backend == .claude { remoteButton }

            ModelPicker(session: session, compact: true, summary: modelSummary.full,
                        color: appearance.style.color(for: session.record.backend))
        }
    }

    // MARK: - Project

    private var projectFolderName: String? {
        session.record.projectFolder == nil ? nil : session.projectName
    }

    private var projectButton: some View {
        Menu {
            Button(session.record.projectFolder == nil ? "Bind to Folder\u{2026}" : "Change Folder\u{2026}") { chooseProject() }
            if let folder = session.record.projectFolder {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
                Button("Open Terminal Here  \u{2325}\u{2318}T") { model.openTerminal() }
                Divider()
                Button("Edit AGENTS.md") { openForEditing(folder + "/AGENTS.md") }
                Button("Edit CLAUDE.md") { openForEditing(folder + "/CLAUDE.md") }
                Divider()
                Button("Unbind from Folder") { session.unbindProject() }
            }
        } label: {
            ToolbarLabel(projectFolderName ?? "No Project", systemImage: session.record.projectFolder == nil ? "folder.badge.plus" : "folder.fill")
        }
        .help(session.record.projectFolder.map { "This chat is bound to \($0). Claude and Codex work in this folder." }
              ?? "Bind this chat to a project folder so Claude or Codex can work in it. Each folder gets one chat.")
    }

    /// Remote Control: whether this chat can be opened on claude.ai and in the Claude app.
    private var remoteButton: some View {
        Menu {
            if let url = session.remoteURL {
                Button("Open on claude.ai") { NSWorkspace.shared.open(url) }
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
                Divider()
                Button("Turn Off Remote Control") { session.setRemoteControl(false) }
            } else if session.wantsRemoteControl {
                Text("Connecting\u{2026}")
                Button("Turn Off Remote Control") { session.setRemoteControl(false) }
            } else {
                Button("Turn On Remote Control") { session.setRemoteControl(true) }
            }
        } label: {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(session.remoteURL != nil ? Color.green : Color.secondary)
        }
        .help(session.remoteURL != nil
              ? "Remote Control is on: this chat is on claude.ai and in the Claude app."
              : "Remote Control: open this chat on claude.ai or in the Claude app")
    }

    /// Stands in for the project button in a Studio chat.
    private func studioButton(_ studio: Studio) -> some View {
        Menu {
            Button("Studio Instructions\u{2026}") { model.editingStudioInstructions = studio.id }
            Button("Fork This Chat") { model.fork(session) }
                .disabled(!model.canFork(session))
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: studio.folder)]) }
            Button("Open Terminal Here  \u{2325}\u{2318}T") { model.openTerminal() }
            Divider()
            Button("Edit AGENTS.md") { openForEditing(studio.folder + "/AGENTS.md") }
            Button("Edit CLAUDE.md") { openForEditing(studio.folder + "/CLAUDE.md") }
            Divider()
            Button("Remove from Studio") { model.move(session, to: nil) }
                .disabled(session.isRunning)
        } label: {
            ToolbarLabel(studio.name, systemImage: "paintpalette")
        }
        .help("This chat is in the \(studio.name) Studio. Its chats share \(studio.folder).")
    }

    private func chooseProject() {
        let start = session.record.projectFolder ?? session.record.codex?.folder
        guard let path = FolderPicker.choose(startingAt: start, message: "Choose the project folder for this chat") else { return }
        if let owner = model.bind(session, to: path) {
            projectConflict = owner
        }
    }

    // MARK: - Model

    /// The model and effort this chat uses, under the message box, with preset buttons.
    @ViewBuilder
    private var modelStatus: some View {
        if compact { compactModelStatus } else { fullModelStatus }
    }

    /// The small floating chat: the model, context, and one menu for the mode and presets.
    private var compactModelStatus: some View {
        HStack(spacing: 8) {
            ModelPicker(session: session, summary: modelSummary.short,
                        color: appearance.style.color(for: session.record.backend),
                        openRequest: commands.modelPopoverRequests)
            UsageMeter(compact: true, session: session, color: appearance.style.color(for: session.record.backend))
                .fixedSize()
            Spacer(minLength: 0)
            Menu {
                Section("Mode") {
                    ForEach(PermissionModes.modes(for: session.record.backend)) { mode in
                        Button { session.setMode(mode.id) } label: {
                            if mode.id == session.mode.id { Label(mode.title, systemImage: "checkmark") } else { Text(mode.title) }
                        }
                    }
                }
                Section("Presets") {
                    ForEach(ModelPresets.shared.presets) { preset in
                        Button(preset.title) { ModelPresets.shared.apply(preset, to: session) }
                    }
                }
            } label: {
                Image(systemName: session.mode.systemImage)
                    .foregroundStyle(session.mode.isUnrestricted ? Color.orange : Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Mode: \(session.mode.title). Presets are here too.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 34)
    }

    private var fullModelStatus: some View {
        HStack(spacing: 10) {
            modeMenu
                .fixedSize()
            // Gives up width first: the name truncates, while the preset pills keep theirs.
            ModelPicker(session: session, summary: modelSummary.full,
                        color: appearance.style.color(for: session.record.backend),
                        openRequest: commands.modelPopoverRequests)
            UsageMeter(session: session, color: appearance.style.color(for: session.record.backend))
            Spacer(minLength: 0)
            PresetPills(session: session, style: appearance.style)
                .fixedSize()
                .layoutPriority(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 34)
    }

    /// How much the active agent may do without asking. Changes apply right away.
    private var modeMenu: some View {
        ModePicker(
            modes: PermissionModes.modes(for: session.record.backend),
            current: session.mode,
            header: session.record.backend == .claude ? "Mode" : "How should Codex actions be approved?",
            showsIcons: session.record.backend == .codex,
            openRequest: commands.modePopoverRequests,
            onSelect: session.setMode
        )
    }
    /// The current agent, model, and effort: a full form, and a short one for narrow windows.
    private var modelSummary: (full: String, short: String) {
        if session.record.backend == .codex, let codex = session.record.codex {
            let models = CodexAppServer.shared.models
            let current = models.first { $0.model == codex.model }
            // With no pick, show what Codex will actually use.
            let resolved = current ?? models.first(where: \.isDefault)
            let name = resolved?.displayName ?? "Codex default"
            let modelName = current == nil && resolved != nil ? "\(name) (default)" : name
            let effort = codex.effort ?? resolved?.defaultEffort
            let effortFull = codex.effort.map { Self.effortLabel($0) } ?? effort.map { "\(Self.effortLabel($0)) (default)" }
            return ("Codex \u{00B7} \(modelName)" + (effortFull.map { " \u{00B7} \($0) effort" } ?? ""),
                    name + (effort.map { " \u{00B7} \(Self.effortLabel($0))" } ?? ""))
        }
        let catalog = ClaudeModels.shared
        let current = catalog.info(session.record.model)
        // "Default" points at a real model; name that one rather than the alias.
        let target = current.value == "default"
            ? catalog.models.first { $0.value != "default" && $0.resolvedModel == current.resolvedModel }?.displayName
            : nil
        let name = target ?? current.displayName
        let modelName = target != nil ? "\(name) (default)" : name
        let effort = session.record.effort.isEmpty ? nil : Self.effortLabel(session.record.effort)
        guard !current.efforts.isEmpty else { return ("Claude \u{00B7} \(modelName)", name) }
        return ("Claude \u{00B7} \(modelName) \u{00B7} \(effort ?? "Default") effort",
                name + " \u{00B7} " + (effort ?? "Default"))
    }

    static func effortLabel(_ effort: String) -> String {
        effort == "xhigh" ? "Extra High" : effort.capitalized
    }

    private func codexBanner(_ status: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(status).lineLimit(2)
            Spacer()
            Button("Open Settings") { model.showingSettings = true }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
    }
}

private struct EmptyChatView: View {
    let session: ChatSession
    let onPick: (String) -> Void

    private var suggestions: [String] {
        if session.record.backend == .codex {
            return [
                "Give me a quick tour of what's in this folder",
                "What looks unfinished or broken in this project?",
                "Explain how the main pieces of this code fit together",
            ]
        }
        return [
            "Help me plan a relaxed weekend in a city I've never been to",
            "What's actually new in the latest macOS release?",
            "I need to write a tricky email. Can you help me think it through?",
        ]
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: session.record.backend == .codex ? "terminal" : "bubble.left.and.text.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.primary)
            Text("What's on your mind?")
                .font(.title2.weight(.semibold))

            AgentSwitch(selection: session.record.backend, onSelect: session.setBackend)

            if session.record.boundFolder == nil, session.record.backend == .codex, let codex = session.record.codex {
                Button {
                    if let path = FolderPicker.choose(startingAt: codex.folder) { session.setCodexFolder(path) }
                } label: {
                    Label(codex.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.link)
                .help("The folder Codex can see. Click to change.")
            }

            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { onPick(suggestion) } label: {
                        Text(suggestion)
                            .frame(maxWidth: 420, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Turns a link with no scheme into the file it names: absolute, "~/…", or relative to the
/// chat's folder, dropping a trailing ":line" or ":line:column" when that's what was added.
enum FileLink {
    static func resolve(_ url: URL, in folder: String) -> URL? {
        guard url.scheme == nil || url.scheme == "file" else { return nil }
        var path = url.scheme == "file" ? url.path : (url.path.removingPercentEncoding ?? url.path)
        guard !path.isEmpty else { return nil }
        path = (path as NSString).expandingTildeInPath
        if !path.hasPrefix("/") { path = (folder as NSString).appendingPathComponent(path) }
        let fm = FileManager.default
        if !fm.fileExists(atPath: path), let range = path.range(of: #":\d+(:\d+)?$"#, options: .regularExpression),
           fm.fileExists(atPath: String(path[..<range.lowerBound])) {
            path = String(path[..<range.lowerBound])
        }
        return URL(fileURLWithPath: path)
    }
}

enum FolderPicker {
    @MainActor
    static func choose(startingAt path: String?, message: String = "Choose the folder Codex can work in") -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = message
        // "New Folder" in the panel, for making a folder on the spot.
        panel.canCreateDirectories = true
        if let path { panel.directoryURL = URL(fileURLWithPath: path) }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

private struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TypingDots(animated: !reduceMotion)
            .frame(width: 26, height: 12)
            .padding(.vertical, 4)
    }
}

/// Three dots in a gentle wave, drawn and animated by Core Animation so SwiftUI does
/// no work per frame.
private struct TypingDots: NSViewRepresentable {
    var animated: Bool

    func makeNSView(context: Context) -> NSView { DotsNSView(animated: animated) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DotsNSView: NSView {
        private var dots: [CALayer] = []

        init(animated: Bool) {
            super.init(frame: .zero)
            wantsLayer = true
            for i in 0..<3 {
                let dot = CALayer()
                dot.backgroundColor = NSColor.secondaryLabelColor.cgColor
                dot.cornerRadius = 3
                dot.opacity = 0.3
                layer?.addSublayer(dot)
                dots.append(dot)
                guard animated else { continue }
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0.3
                fade.toValue = 1
                let rise = CABasicAnimation(keyPath: "transform.translation.y")
                rise.fromValue = 0
                rise.toValue = 2.5
                let group = CAAnimationGroup()
                group.animations = [fade, rise]
                group.duration = 0.5
                group.autoreverses = true
                group.repeatCount = .infinity
                group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                group.beginTime = CACurrentMediaTime() + Double(i) * 0.16
                dot.add(group, forKey: "wave")
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            for (i, dot) in dots.enumerated() {
                dot.frame = CGRect(x: CGFloat(i) * 10, y: bounds.midY - 3, width: 6, height: 6)
            }
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            effectiveAppearance.performAsCurrentDrawingAppearance {
                for dot in dots { dot.backgroundColor = NSColor.secondaryLabelColor.cgColor }
            }
        }
    }
}

/// A removable attachment in the composer.
private struct AttachmentChip: View {
    let attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            AttachmentThumbnail(attachment: attachment, size: 28)
            Text(attachment.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: 160, alignment: .leading)
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove")
        }
        .font(.callout)
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.7)))
    }
}

/// The mode button under the message box and its popover: each mode with its description,
/// a Recommended badge, and number keys to pick one.
private struct ModePicker: View {
    let modes: [PermissionMode]
    let current: PermissionMode
    let header: String
    let showsIcons: Bool
    /// Bumped by Chat → Choose Mode (⌘⇧P) to toggle the popover.
    var openRequest = 0
    let onSelect: (String) -> Void
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 3) {
                Label(current.title, systemImage: current.systemImage).labelStyle(SpacedLabelStyle())
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(current.isUnrestricted ? Color.orange : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(current.title): \(current.detail). Click to change (\u{2318}\u{21E7}P).")
        .onChange(of: openRequest) { isOpen.toggle() }
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(header)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                    ModeRow(mode: mode, number: index + 1, isCurrent: mode.id == current.id, showsIcon: showsIcons) {
                        onSelect(mode.id)
                        isOpen = false
                    }
                }
            }
            .padding(10)
            .frame(width: 380)
        }
    }
}

private struct ModeRow: View {
    let mode: PermissionMode
    let number: Int
    let isCurrent: Bool
    let showsIcon: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(alignment: .center, spacing: 10) {
                if showsIcon {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 15))
                        .frame(width: 20)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mode.title).font(.body)
                        if mode.isRecommended {
                            Text("Recommended")
                                .font(.caption)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(mode.detail)
                        .font(.callout)
                        .foregroundStyle(mode.isUnrestricted ? AnyShapeStyle(Color.orange.opacity(0.85)) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "checkmark").foregroundStyle(Color.highlight)
                }
                Text("\(number)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(mode.isUnrestricted ? Color.orange : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.primary.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: [])
    }
}

/// The project's GitHub repo in the toolbar: branch and sync state, with links out.
private struct RepoChip: View {
    let repo: String
    let remote: GitRemote
    let status: GitStatus
    let folder: String
    let onSelectRemote: (String) -> Void
    let onShowIssues: () -> Void

    private var web: URL { URL(string: "https://github.com/\(repo)")! }

    private var syncText: String {
        var parts: [String] = []
        if let ahead = status.ahead, ahead > 0 { parts.append("\u{2191}\(ahead)") }
        if let behind = status.behind, behind > 0 { parts.append("\u{2193}\(behind)") }
        return parts.joined(separator: " ")
    }

    var body: some View {
        Menu {
            Button("Open on GitHub") { NSWorkspace.shared.open(web) }
            if let branch = status.branch {
                Button("Open Branch \u{201C}\(branch)\u{201D}") {
                    NSWorkspace.shared.open(web.appendingPathComponent("tree").appendingPathComponent(branch))
                }
            }
            Button("Issues\u{2026}") { onShowIssues() }
            Button("Issues on GitHub") { NSWorkspace.shared.open(web.appendingPathComponent("issues")) }
            Button("Pull Requests") { NSWorkspace.shared.open(web.appendingPathComponent("pulls")) }
            Divider()
            Button("Copy Clone URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(remote.url, forType: .string)
            }
            Button(GitStatusStore.shared.fetching.contains(folder) ? "Checking GitHub\u{2026}" : "Check for Updates") {
                Task { await GitStatusStore.shared.refresh(folder, fetch: true) }
            }
            let github = status.remotes.filter { $0.repo != nil }
            if github.count > 1 {
                Divider()
                Picker("Remote", selection: Binding(get: { remote.name }, set: onSelectRemote)) {
                    ForEach(github, id: \.name) { Text("\($0.name) (\($0.repo ?? ""))").tag($0.name) }
                }
            }
        } label: {
            ToolbarLabel([repo, status.branch, syncText.isEmpty ? nil : syncText].compactMap { $0 }.joined(separator: " \u{00B7} "),
                         systemImage: "arrow.triangle.branch")
        }
        .help(helpText)
    }

    private var helpText: String {
        var text = "\(repo) on GitHub (remote \u{201C}\(remote.name)\u{201D})"
        if let branch = status.branch { text += ", branch \(branch)" }
        if let ahead = status.ahead, let behind = status.behind {
            text += ". \(ahead) to push, \(behind) to pull"
        } else {
            text += ". No upstream branch"
        }
        return text + "."
    }
}

/// A toolbar menu's icon and title with a gap between them. The toolbar restyles a `Label`
/// (ignoring any label style), so this is a plain row it leaves alone.
struct ToolbarLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title).lineLimit(1)
        }
    }
}

/// Icon then title with a little breathing room, for status controls.
struct SpacedLabelStyle: LabelStyle {
    var spacing: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

/// Claude | Codex on an empty chat. A system segmented control always takes the macOS accent
/// color (blue); this one marks the choice in the text color instead: white in dark mode.
private struct AgentSwitch: View {
    let selection: Backend
    let onSelect: (Backend) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Backend.allCases) { backend in
                let selected = backend == selection
                Button { onSelect(backend) } label: {
                    Text(backend.label)
                        .font(.callout.weight(.medium))
                        .frame(width: 96, height: 24)
                        .foregroundStyle(selected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.primary : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chat with")
    }
}
