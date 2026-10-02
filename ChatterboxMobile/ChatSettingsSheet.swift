import SwiftUI

/// A chat's agent, model, effort, mode, and presets, as on the Mac. Each change applies
/// right away, even mid-reply.
struct ChatSettingsSheet: View {
    let options: Companion.ChatOptions
    let apply: (Companion.SettingsRequest) -> Void
    @Environment(\.dismiss) private var dismiss

    private var isCodex: Bool { options.backend == "codex" }
    private var models: [Companion.ModelOption] { isCodex ? options.codexModels : options.claudeModels }
    private var currentModel: Companion.ModelOption? { models.first { $0.id == options.model } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Agent") {
                    Picker("Agent", selection: Binding(get: { options.backend }, set: { apply(.init(backend: $0)) })) {
                        Text("Claude").tag("claude")
                        Text("Codex").tag("codex")
                    }
                    .pickerStyle(.segmented)
                }

                if !options.presets.isEmpty {
                    Section("Presets") {
                        ForEach(options.presets) { preset in
                            Button { apply(.init(preset: preset.id)) } label: {
                                row(preset.title, detail: preset.backend == "codex" ? "Codex" : "Claude", isOn: preset.isActive)
                            }
                        }
                    }
                }

                Section("Model") {
                    if models.isEmpty {
                        Text("Models load once \(isCodex ? "Codex" : "Claude Code") starts on the Mac.").foregroundStyle(.secondary)
                    }
                    ForEach(models) { model in
                        Button { apply(.init(model: model.id)) } label: {
                            row(model.name, detail: model.detail, isOn: model.id == options.model)
                        }
                    }
                }

                if let efforts = currentModel?.efforts, !efforts.isEmpty {
                    Section("Effort") {
                        Picker("Effort", selection: Binding(get: { options.effort }, set: { apply(.init(effort: $0)) })) {
                            Text(currentModel?.defaultEffort.map { "Default (\(Self.label($0)))" } ?? "Default").tag("")
                            ForEach(efforts, id: \.self) { Text(Self.label($0)).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                if isCodex, let fast = options.fastMode {
                    Section {
                        Toggle("Fast mode", isOn: Binding(get: { fast }, set: { apply(.init(fastMode: $0)) }))
                    } footer: {
                        Text("Faster replies with higher usage. Applies to the next reply; availability depends on your model and plan.")
                    }
                }

                Section("Mode") {
                    ForEach(options.modes) { mode in
                        Button { apply(.init(mode: mode.id)) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: mode.systemImage)
                                    .foregroundStyle(mode.isUnrestricted ? .orange : .secondary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.title).foregroundStyle(mode.isUnrestricted ? .orange : .primary)
                                    if !mode.detail.isEmpty { Text(mode.detail).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if mode.id == options.mode { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                }
            }
            // Choices read as plain rows with a checkmark, not blue links.
            .buttonStyle(ChoiceRowStyle())
            .navigationTitle("Chat Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func row(_ title: String, detail: String, isOn: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if isOn { Image(systemName: "checkmark").foregroundStyle(.tint) }
        }
    }

    /// "xhigh" → "Extra High", the way the Mac names them.
    static func label(_ effort: String) -> String {
        effort == "xhigh" ? "Extra High" : effort.capitalized
    }
}

/// A whole-row button in a form, in the text's own colors.
private struct ChoiceRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
