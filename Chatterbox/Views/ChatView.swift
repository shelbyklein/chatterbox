import AppKit
import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var model
    let session: ChatSession
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if session.record.backend == .claude && !model.hasAPIKey { apiKeyBanner }
            if session.record.backend == .codex, let status = CodexAppServer.shared.statusMessage { codexBanner(status) }
            transcript
            composer
        }
        .navigationTitle(session.title)
        .toolbar { toolbarContent }
        .onAppear { composerFocused = true }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if session.items.isEmpty {
                    EmptyChatView(session: session) { draft = $0; submit() }
                        .padding(.top, 60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(session.items) { item in
                            ItemView(item: item, onApproval: session.resolveApproval)
                                .id(item.id)
                        }
                        if session.isRunning && !isVisiblyWorking {
                            TypingIndicator()
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: session.items.count) { scrollToBottom(proxy) }
            .onChange(of: session.items.last?.text) { scrollToBottom(proxy) }
        }
    }

    /// True when the last row already shows activity, so the typing dots would be redundant.
    private var isVisiblyWorking: Bool {
        guard let last = session.items.last else { return false }
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
        HStack(alignment: .bottom, spacing: 10) {
            TextField(session.isRunning ? "Add something while it works\u{2026}" : "Message \(session.record.backend.label)", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($composerFocused)
                .onSubmit(submit)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))

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
            .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(session.isRunning ? "Steer the current reply" : "Send")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func submit() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        session.send(text)
        model.refreshAPIKeyState()
    }

    private var apiKeyBanner: some View {
        HStack {
            Image(systemName: "key.fill")
            Text("Add your Anthropic API key to start chatting.")
            Spacer()
            SettingsLink { Text("Open Settings") }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.15))
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

            if let codex = session.record.codex {
                Button { chooseFolder() } label: {
                    Label((codex.folder as NSString).lastPathComponent, systemImage: "folder")
                        .labelStyle(.titleAndIcon)
                }
                .help("Codex works in \(codex.folder)")

                Toggle(isOn: Binding(get: { codex.canEdit }, set: session.setCodexCanEdit)) {
                    Label("Can edit", systemImage: "pencil")
                }
                .help(codex.canEdit ? "Codex can change files in this folder" : "Codex can only read files")

                codexModelMenu(codex)
            } else {
                Toggle(isOn: Binding(get: { session.record.webAccess }, set: session.setWebAccess)) {
                    Label("Web", systemImage: "globe")
                }
                .help("Let Claude search and read the web")

                claudeModelMenu
            }
        }
    }

    private var claudeModelMenu: some View {
        let catalog = ClaudeModels.shared
        let current = catalog.info(session.record.model)
        // Keep a chat's model selectable even if the API no longer lists it.
        let models = catalog.models.contains { $0.id == current.id } ? catalog.models : [current] + catalog.models
        return Menu {
            Picker("Model", selection: Binding(get: { session.record.model }, set: session.setModel)) {
                ForEach(models) { Text($0.displayName).tag($0.id) }
            }
            if !current.efforts.isEmpty {
                Picker("Effort", selection: Binding(get: { current.coerce(effort: session.record.effort) }, set: session.setEffort)) {
                    ForEach(current.efforts, id: \.self) { Text(Self.effortLabel($0)).tag($0) }
                }
            }
            Divider()
            Button("Refresh Model List") { Task { await catalog.refresh(force: true) } }
            if let error = catalog.errorMessage { Text("Couldn't load models: \(error)") }
        } label: {
            Label("Model", systemImage: "cpu")
        }
        .help(current.efforts.isEmpty
              ? current.displayName
              : "\(current.displayName), \(Self.effortLabel(current.coerce(effort: session.record.effort)).lowercased()) effort")
        .task(id: model.hasAPIKey) { await catalog.refresh() }
    }

    static func effortLabel(_ effort: String) -> String {
        effort == "xhigh" ? "Extra High" : effort.capitalized
    }

    private func codexModelMenu(_ codex: CodexSettings) -> some View {
        let models = CodexAppServer.shared.models
        let current = models.first { $0.model == codex.model }
        return Menu {
            Picker("Model", selection: Binding(get: { codex.model ?? "" }, set: { session.setCodexModel($0.isEmpty ? nil : $0) })) {
                Text("Codex default").tag("")
                ForEach(models.filter { !$0.hidden || $0.model == codex.model }) { Text($0.displayName).tag($0.model) }
            }
            let hidden = models.filter { $0.hidden && $0.model != codex.model }
            if !hidden.isEmpty {
                Menu("More Models") {
                    ForEach(hidden) { m in Button(m.displayName) { session.setCodexModel(m.model) } }
                }
            }
            Picker("Effort", selection: Binding(get: { codex.effort ?? "" }, set: { session.setCodexEffort($0.isEmpty ? nil : $0) })) {
                Text("Model default").tag("")
                ForEach(current?.efforts ?? ["low", "medium", "high"], id: \.self) { Text(Self.effortLabel($0)).tag($0) }
            }
        } label: {
            Label("Model", systemImage: "cpu")
        }
        .help("\(current?.displayName ?? "Codex default model")\(codex.effort.map { ", \($0) effort" } ?? "")")
        .task { if models.isEmpty { try? await CodexAppServer.shared.refreshModels() } }
    }

    private func chooseFolder() {
        if let path = FolderPicker.choose(startingAt: session.record.codex?.folder) {
            session.setCodexFolder(path)
        }
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

            if let codex = session.record.codex {
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
    static func choose(startingAt path: String?) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder Codex can work in"
        if let path { panel.directoryURL = URL(fileURLWithPath: path) }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

private struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .frame(width: 6, height: 6)
                    .opacity(0.3 + 0.7 * max(0, sin(phase - Double(i) * 0.8)))
            }
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi * 2 }
        }
    }
}
