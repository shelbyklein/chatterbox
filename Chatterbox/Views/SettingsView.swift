import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var keyDraft = ""
    @State private var status: String?
    @State private var detectedCodex: String?

    @AppStorage("defaultBackend") private var defaultBackend = Backend.claude
    @AppStorage("defaultModel") private var defaultModel = "claude-opus-5"
    @AppStorage("defaultEffort") private var defaultEffort = "high"
    @AppStorage("codexDefaultModel") private var codexDefaultModel = ""
    @AppStorage("codexDefaultEffort") private var codexDefaultEffort = ""
    @AppStorage("defaultPersonality") private var defaultPersonality = Personality.friendly
    @AppStorage("webAccess") private var webAccess = true
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("codexFolder") private var codexFolder = NSHomeDirectory()
    @AppStorage("codexCanEdit") private var codexCanEdit = false

    var body: some View {
        Form {
            Section("New chats") {
                Picker("Chat with", selection: $defaultBackend) {
                    ForEach(Backend.allCases) { Text($0.label).tag($0) }
                }
                Picker("Tone", selection: $defaultPersonality) {
                    ForEach(Personality.allCases) { Text($0.label).tag($0) }
                }
            }

            Section {
                SecureField("API key", text: $keyDraft, prompt: Text(model.hasAPIKey ? "Saved. Paste a new key to replace it" : "sk-ant-\u{2026}"))
                HStack {
                    Button("Save Key") {
                        status = Keychain.saveAPIKey(keyDraft) ? "Saved to your keychain." : "Couldn't save to the keychain."
                        keyDraft = ""
                        model.refreshAPIKeyState()
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if model.hasAPIKey {
                        Button("Remove Key", role: .destructive) {
                            Keychain.deleteAPIKey()
                            model.refreshAPIKeyState()
                            status = "Removed."
                        }
                    }
                    Spacer()
                    if let status { Text(status).foregroundStyle(.secondary).font(.caption) }
                }
                claudeDefaults
                Toggle("Web search and page reading", isOn: $webAccess)
            } header: {
                Text("Claude")
            } footer: {
                HStack {
                    Text("Uses your Anthropic API key. Web search is billed per search.")
                    Spacer()
                    Link("Get a key", destination: URL(string: "https://platform.claude.com/settings/keys")!)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Default folder") {
                    Button((codexFolder as NSString).abbreviatingWithTildeInPath) {
                        if let path = FolderPicker.choose(startingAt: codexFolder) { codexFolder = path }
                    }
                }
                Toggle("Allow edits in that folder by default", isOn: $codexCanEdit)
                codexDefaults
                TextField("codex path", text: $codexPath, prompt: Text(detectedCodex ?? "Auto-detect"))
            } header: {
                Text("Codex")
            } footer: {
                Text(detectedCodex == nil
                     ? "Couldn't find the `codex` command. Install the Codex CLI, or enter its full path."
                     : "Uses your installed Codex CLI, its config, and your ChatGPT sign-in. Codex asks before running commands that need approval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: codexPath) { detectedCodex = CodexAppServer.locateBinary() }
        .task(id: model.hasAPIKey) { await ClaudeModels.shared.refresh() }
        .task { if CodexAppServer.shared.models.isEmpty { try? await CodexAppServer.shared.refreshModels() } }
    }

    @ViewBuilder
    private var claudeDefaults: some View {
        let catalog = ClaudeModels.shared
        let current = catalog.info(defaultModel)
        let models = catalog.models.contains { $0.id == current.id } ? catalog.models : [current] + catalog.models
        Picker("Model", selection: Binding(get: { defaultModel }, set: {
            defaultModel = $0
            defaultEffort = catalog.info($0).coerce(effort: defaultEffort)
        })) {
            ForEach(models) { Text($0.displayName).tag($0.id) }
        }
        if !current.efforts.isEmpty {
            Picker("Effort", selection: Binding(get: { current.coerce(effort: defaultEffort) }, set: { defaultEffort = $0 })) {
                ForEach(current.efforts, id: \.self) { Text(ChatView.effortLabel($0)).tag($0) }
            }
        }
    }

    @ViewBuilder
    private var codexDefaults: some View {
        let models = CodexAppServer.shared.models
        let current = models.first { $0.model == codexDefaultModel }
        Picker("Model", selection: Binding(get: { codexDefaultModel }, set: { codexDefaultModel = $0; codexDefaultEffort = "" })) {
            Text("Codex default").tag("")
            if !codexDefaultModel.isEmpty && current == nil { Text(codexDefaultModel).tag(codexDefaultModel) }
            ForEach(models) { Text($0.displayName + ($0.hidden ? " (hidden)" : "")).tag($0.model) }
        }
        Picker("Effort", selection: $codexDefaultEffort) {
            Text("Model default").tag("")
            ForEach(current?.efforts ?? ["low", "medium", "high"], id: \.self) { Text(ChatView.effortLabel($0)).tag($0) }
        }
    }
}
