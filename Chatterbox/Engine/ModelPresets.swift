import Foundation
import Observation

/// One-click agent + model + effort combinations, shown next to the model line.
struct ModelPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var backend: Backend
    /// Claude model id, or Codex model (nil means Codex's default).
    var model: String?
    /// nil means the model's default effort.
    var effort: String?
}

@MainActor
@Observable
final class ModelPresets {
    static let shared = ModelPresets()

    private(set) var presets: [ModelPreset]
    private let key = "modelPresets"

    static let defaults: [ModelPreset] = [
        ModelPreset(title: "Opus 5.5 \u{00B7} Medium", backend: .claude, model: "claude-opus-5-5", effort: "medium"),
        ModelPreset(title: "Astra \u{00B7} Low", backend: .codex, model: "gpt-6-astra", effort: "low"),
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([ModelPreset].self, from: data) {
            presets = saved
        } else {
            presets = Self.defaults
        }
    }

    func apply(_ preset: ModelPreset, to session: ChatSession) {
        session.setBackend(preset.backend)
        guard session.record.backend == preset.backend else { return } // a turn is still running
        switch preset.backend {
        case .claude:
            if let model = preset.model { session.setModel(model) }
            session.setEffort(preset.effort ?? "")
        case .codex:
            session.setCodexModel(preset.model)
            session.setCodexEffort(preset.effort)
        }
    }

    func matches(_ preset: ModelPreset, session: ChatSession) -> Bool {
        guard session.record.backend == preset.backend else { return false }
        switch preset.backend {
        case .claude:
            return preset.model.map { ClaudeModels.shared.sameModel($0, session.record.model) } ?? true
                && (preset.effort ?? "") == session.record.effort
        case .codex:
            return preset.model == session.record.codex?.model && preset.effort == session.record.codex?.effort
        }
    }

    /// Saves the chat's current agent, model, and effort as a new preset.
    func saveCurrent(_ session: ChatSession, title: String) {
        let record = session.record
        let preset = record.backend == .claude
            ? ModelPreset(title: title, backend: .claude, model: record.model, effort: record.effort.isEmpty ? nil : record.effort)
            : ModelPreset(title: title, backend: .codex, model: record.codex?.model, effort: record.codex?.effort)
        guard !presets.contains(where: { $0.backend == preset.backend && $0.model == preset.model && $0.effort == preset.effort }) else { return }
        presets.append(preset)
        save()
    }

    func remove(_ preset: ModelPreset) {
        presets.removeAll { $0.id == preset.id }
        save()
    }

    func rename(_ preset: ModelPreset, to title: String) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }), !title.isEmpty else { return }
        presets[index].title = title
        save()
    }

    /// Moves a preset to where `target` is, for drag-to-reorder in the preset row.
    func move(_ id: UUID, to target: UUID) {
        guard id != target, let from = presets.firstIndex(where: { $0.id == id }),
              let to = presets.firstIndex(where: { $0.id == target }) else { return }
        presets.insert(presets.remove(at: from), at: to)
        save()
    }

    func resetToDefaults() {
        presets = Self.defaults
        save()
    }


    private func save() {
        if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: key) }
    }
}
