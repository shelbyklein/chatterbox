import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var detectedCodex: String?
    @State private var detectedClaude: String?

    @AppStorage("defaultBackend") private var defaultBackend = Backend.claude
    @AppStorage("defaultModel") private var defaultModel = "default"
    @AppStorage("defaultEffort") private var defaultEffort = ""
    @AppStorage("codexDefaultModel") private var codexDefaultModel = ""
    @AppStorage("codexDefaultEffort") private var codexDefaultEffort = ""
    @AppStorage("defaultPersonality") private var defaultPersonality = Personality.friendly
    @AppStorage("claudePath") private var claudePath = ""
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("codexFolder") private var codexFolder = NSHomeDirectory()
    @AppStorage("claudeDefaultMode") private var claudeDefaultMode = PermissionModes.defaultClaude
    @AppStorage("codexDefaultMode") private var codexDefaultMode = PermissionModes.defaultCodex

    var body: some View {
        Form {
            Section("New chats") {
                Picker("Chat with", selection: $defaultBackend) {
                    ForEach(Backend.allCases) { Text($0.label).tag($0) }
                }
                Picker("Tone", selection: $defaultPersonality) {
                    ForEach(Personality.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Working folder") {
                    Button((codexFolder as NSString).abbreviatingWithTildeInPath) {
                        if let path = FolderPicker.choose(startingAt: codexFolder, message: "Choose where chats without a project work") { codexFolder = path }
                    }
                }
                .help("Where Claude Code and Codex work in chats that aren't bound to a project folder.")
                Picker("Claude mode", selection: $claudeDefaultMode) {
                    ForEach(PermissionModes.claude) { Text($0.title).tag($0.id) }
                }
                Picker("Codex mode", selection: $codexDefaultMode) {
                    ForEach(PermissionModes.codex) { Text($0.title).tag($0.id) }
                }
            }

            Section {
                LabeledContent("Signed in") {
                    if let email = ClaudeModels.shared.accountEmail {
                        Text(email + (ClaudeModels.shared.plan.map { " (\($0))" } ?? ""))
                    } else {
                        Text(ClaudeModels.shared.statusMessage ?? "Checking\u{2026}").foregroundStyle(.secondary)
                    }
                }
                claudeDefaults
                TextField("claude path", text: $claudePath, prompt: Text(detectedClaude ?? "Auto-detect"))
            } header: {
                Text("Claude Code")
            } footer: {
                Text(detectedClaude == nil
                     ? "Couldn't find the `claude` command. Install Claude Code, or enter its full path."
                     : "Uses your installed Claude Code, its settings, and your Claude subscription. The mode under the message box decides what Claude may do without asking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ModelPresets.shared.presets) { preset in
                    HStack {
                        TextField("Name", text: Binding(get: { preset.title }, set: { ModelPresets.shared.rename(preset, to: $0) }))
                            .textFieldStyle(.plain)
                        Spacer()
                        Text(presetDetail(preset)).foregroundStyle(.secondary).font(.caption)
                        Button { ModelPresets.shared.remove(preset) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Remove preset")
                    }
                }
                Button("Restore Default Presets") { ModelPresets.shared.resetToDefaults() }
            } header: {
                Text("Quick-switch presets")
            } footer: {
                Text("Shown under the message box. Add one from the model menu with \u{201C}Save as Preset\u{201D}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
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
        .task(id: claudePath) {
            detectedClaude = ClaudeCodeProcess.locateBinary()
            await ClaudeModels.shared.refresh(force: !claudePath.isEmpty)
        }
        .task { if CodexAppServer.shared.models.isEmpty { try? await CodexAppServer.shared.refreshModels() } }
    }

    private func presetDetail(_ preset: ModelPreset) -> String {
        let model = preset.model ?? "default model"
        return "\(preset.backend.label) \u{00B7} \(model) \u{00B7} \(preset.effort.map { ChatView.effortLabel($0) } ?? "default effort")"
    }

    @ViewBuilder
    private var claudeDefaults: some View {
        let catalog = ClaudeModels.shared
        let current = catalog.info(defaultModel)
        let models = catalog.models.contains { $0.value == current.value } ? catalog.models : [current] + catalog.models
        Picker("Model", selection: Binding(get: { current.value }, set: {
            defaultModel = $0
            if !catalog.info($0).efforts.contains(defaultEffort) { defaultEffort = "" }
        })) {
            ForEach(models) { Text($0.displayName).tag($0.value) }
        }
        if !current.efforts.isEmpty {
            Picker("Effort", selection: $defaultEffort) {
                Text("Model default").tag("")
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
