import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(AppModel.self) private var model
    let session: ChatSession
    @State private var draft = ""
    @State private var attachments: [Attachment] = []
    @State private var attachError: String?
    @State private var isDropTargeted = false
    @State private var pasteMonitor: Any?
    @State private var projectConflict: ChatSession?
    @State private var reviewing: Attachment?
    private let presets = ModelPresets.shared
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
        // Re-read git when the chat opens, its folder changes, or a turn ends (the agent may have committed).
        .task(id: "\(session.record.projectFolder ?? "")|\(session.isRunning)") {
            guard let folder = session.record.projectFolder, !session.isRunning else { return }
            await GitStatusStore.shared.refresh(folder)
            session.updateGitHubRepo(from: GitStatusStore.shared.status(for: folder))
        }
        .onAppear {
            composerFocused = true
            installPasteMonitor()
        }
        .onDisappear {
            if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
            pasteMonitor = nil
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted, perform: handleDrop)
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
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(Color.accentColor.opacity(0.06))
                    .overlay(Label("Drop to attach", systemImage: "paperclip").font(.title3).foregroundStyle(.tint))
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
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        do { add([try Attachments.importImageData(data, name: "Dropped image")]) } catch { attachError = error.localizedDescription }
                    }
                }
            }
        }
        return true
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
                            ItemView(item: item, isActive: session.isRunning && item.id == session.items.last?.id,
                                     agent: agents[item.id] ?? session.record.backend,
                                     onApproval: session.resolveApproval)
                                .padding(.vertical, rowPadding(item))
                                .id(item.id)
                        }
                        if session.isRunning && !isVisiblyWorking {
                            TypingIndicator()
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
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
        default: return false
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty { attachmentTray }
            if let attachError {
                Label(attachError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            composerRow
            modelStatus
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: appearance.style.contentWidth + 40)
        .frame(maxWidth: .infinity)
        .background(.bar)
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

            TextField(session.isRunning ? "Add something while it works\u{2026}" : "Message \(session.record.backend.label)", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($composerFocused)
                .onSubmit(submit)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(appearance.style.color(for: session.record.backend).opacity(composerFocused ? 0.8 : 0.45),
                                  lineWidth: composerFocused ? 1.5 : 1))
                .animation(.easeOut(duration: 0.15), value: session.record.backend)

            if session.isRunning {
                Button(action: session.interrupt) {
                    Image(systemName: "stop.circle.fill").font(.system(size: 26))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(".", modifiers: .command)
                .help("Stop (\u{2318}.)")
            }

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 26))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            .disabled(!canSend)
            .help(session.isRunning ? "Steer the current reply" : "Send")
        }
    }

    private func submit() {
        guard canSend else { return }
        let text = draft
        let files = attachments
        draft = ""
        attachments = []
        attachError = nil
        session.send(text, attachments: files)
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
            SettingsLink { Text("Open Settings") }
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
            Picker("Tone", selection: Binding(get: { session.record.personality }, set: session.setPersonality)) {
                ForEach(Personality.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Tone. Changes apply from your next message.")

            projectButton
            if let status = GitStatusStore.shared.status(for: session.record.projectFolder),
               let remote = status.remote(preferring: session.record.gitRemote), let repo = remote.repo {
                RepoChip(repo: repo, remote: remote, status: status, folder: session.record.projectFolder ?? "",
                         onSelectRemote: session.setGitRemote)
            }

            modelMenu(inline: false)
        }
    }

    // MARK: - Project

    private var projectFolderName: String? {
        session.record.projectFolder.map { ($0 as NSString).lastPathComponent }
    }

    private var projectButton: some View {
        Menu {
            Button(session.record.projectFolder == nil ? "Bind to Folder\u{2026}" : "Change Folder\u{2026}") { chooseProject() }
            if let folder = session.record.projectFolder {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
                Divider()
                Button("Unbind from Folder") { session.unbindProject() }
            }
        } label: {
            Label(projectFolderName ?? "No Project", systemImage: session.record.projectFolder == nil ? "folder.badge.plus" : "folder.fill")
                .labelStyle(.titleAndIcon)
        }
        .help(session.record.projectFolder.map { "This chat is bound to \($0). Claude and Codex work in this folder." }
              ?? "Bind this chat to a project folder so Claude or Codex can work in it. Each folder gets one chat.")
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
    private var modelStatus: some View {
        HStack(spacing: 10) {
            modeMenu
                .fixedSize()
            // Gives up width first: the label shortens, then shows just the icon.
            modelMenu(inline: true)
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
            Spacer(minLength: 0)
            ForEach(presets.presets) { preset in
                let active = presets.matches(preset, session: session)
                Button { presets.apply(preset, to: session) } label: {
                    Text(preset.title)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(active ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12)))
                        .foregroundStyle(active ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(session.isRunning && preset.backend != session.record.backend)
                .help(active ? "Using \(preset.title)" : "Switch to \(preset.title)")
                .layoutPriority(1)
            }
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

    /// One menu for both agents. Picking a model from the other agent switches this chat to it.
    private func modelMenu(inline: Bool) -> some View {
        let catalog = ClaudeModels.shared
        let codexModels = CodexAppServer.shared.models
        let onClaude = session.record.backend == .claude
        let claudeCurrent = catalog.info(session.record.model)
        // Keep a chat's model selectable even if Claude Code no longer lists it.
        let claudeModels = catalog.models.contains { $0.value == claudeCurrent.value } ? catalog.models : [claudeCurrent] + catalog.models
        let codex = session.record.codex
        let codexCurrent = codexModels.first { $0.model == codex?.model }
        let summary = modelSummary

        return Menu {
            Section("Claude") {
                ForEach(claudeModels) { m in
                    Button { selectClaude(m.value) } label: {
                        checkmarked(m.displayName, onClaude && m.value == claudeCurrent.value)
                    }
                    .disabled(session.isRunning && !onClaude)
                    .help(m.detail)
                }
            }
            Section("Codex") {
                Button { selectCodex(nil) } label: { checkmarked("Codex default", !onClaude && codex?.model == nil) }
                    .disabled(session.isRunning && onClaude)
                ForEach(codexModels.filter { !$0.hidden || $0.model == codex?.model }) { m in
                    Button { selectCodex(m.model) } label: { checkmarked(m.displayName, !onClaude && m.model == codex?.model) }
                        .disabled(session.isRunning && onClaude)
                }
                let hidden = codexModels.filter { $0.hidden && $0.model != codex?.model }
                if !hidden.isEmpty {
                    Menu("More Codex Models") {
                        ForEach(hidden) { m in Button(m.displayName) { selectCodex(m.model) } }
                    }
                    .disabled(session.isRunning && onClaude)
                }
            }
            Divider()
            if onClaude {
                if !claudeCurrent.efforts.isEmpty {
                    Picker("Effort", selection: Binding(get: { session.record.effort }, set: session.setEffort)) {
                        Text("Model default").tag("")
                        ForEach(claudeCurrent.efforts, id: \.self) { Text(Self.effortLabel($0)).tag($0) }
                    }
                }
            } else if let codex {
                Picker("Effort", selection: Binding(get: { codex.effort ?? "" }, set: { session.setCodexEffort($0.isEmpty ? nil : $0) })) {
                    Text("Model default").tag("")
                    ForEach(codexCurrent?.efforts ?? ["low", "medium", "high"], id: \.self) { Text(Self.effortLabel($0)).tag($0) }
                }
            }
            Divider()
            Button("Save as Preset") { presets.saveCurrent(session, title: summary.short) }
            Button("Refresh Model Lists") {
                Task {
                    await catalog.refresh(force: true)
                    try? await CodexAppServer.shared.refreshModels()
                }
            }
            if let error = catalog.statusMessage { Text(error) }
        } label: {
            if inline {
                ViewThatFits(in: .horizontal) {
                    Label { Text(summary.full).lineLimit(1) } icon: { agentDot }
                    Label { Text(summary.short).lineLimit(1) } icon: { agentDot }
                    Label { Text(summary.short) } icon: { agentDot }.labelStyle(.iconOnly)
                }
            } else {
                Label("Model", systemImage: "cpu")
            }
        }
        .help(summary.full + ". Click to change.")
        .task { await catalog.refresh() }
        .task { if codexModels.isEmpty { try? await CodexAppServer.shared.refreshModels() } }
    }

    /// The current agent's color, next to the model name.
    private var agentDot: some View {
        Circle().fill(appearance.style.color(for: session.record.backend)).frame(width: 8, height: 8)
    }

    @ViewBuilder
    private func checkmarked(_ title: String, _ on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func selectClaude(_ id: String) {
        session.setBackend(.claude)
        session.setModel(id)
    }

    private func selectCodex(_ id: String?) {
        session.setBackend(.codex)
        session.setCodexModel(id)
    }

    static func effortLabel(_ effort: String) -> String {
        effort == "xhigh" ? "Extra High" : effort.capitalized
    }

    private func codexBanner(_ status: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(status).lineLimit(2)
            Spacer()
            SettingsLink { Text("Open Settings") }
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
                .foregroundStyle(.tint)
            Text("What's on your mind?")
                .font(.title2.weight(.semibold))

            Picker("Chat with", selection: Binding(get: { session.record.backend }, set: session.setBackend)) {
                ForEach(Backend.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)

            if session.record.projectFolder == nil, session.record.backend == .codex, let codex = session.record.codex {
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

enum FolderPicker {
    @MainActor
    static func choose(startingAt path: String?, message: String = "Choose the folder Codex can work in") -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = message
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
    let onSelect: (String) -> Void
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 3) {
                Label(current.title, systemImage: current.systemImage).labelStyle(.titleAndIcon)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(current.isUnrestricted ? Color.orange : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(current.title): \(current.detail). Click to change.")
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
                    Image(systemName: "checkmark").foregroundStyle(.tint)
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
            Button("Issues") { NSWorkspace.shared.open(web.appendingPathComponent("issues")) }
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
            Label {
                Text([repo, status.branch, syncText.isEmpty ? nil : syncText].compactMap { $0 }.joined(separator: " \u{00B7} "))
            } icon: {
                Image(systemName: "arrow.triangle.branch")
            }
            .labelStyle(.titleAndIcon)
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
