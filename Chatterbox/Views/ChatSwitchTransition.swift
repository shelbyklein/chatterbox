import SwiftUI

/// Mounts a new keyed chat only after the outgoing transcript has faded away.
/// Owned above ChatView, so changing its identity cannot reset the transition.
@MainActor @Observable
final class ChatSwitchTransition {
    private(set) var initialized = false
    private(set) var displayedID: UUID?
    private(set) var opacity = 1.0
    private(set) var offset = 0.0
    private(set) var switching = false
    private var generation = 0
    private var mountedID: UUID?

    func didMount(_ id: UUID) { mountedID = id }

    func show(_ id: UUID?, reduceMotion: Bool, waitForMount: Bool = false) async {
        generation += 1
        let ticket = generation
        if !initialized || id == nil || displayedID == nil || id == displayedID {
            initialized = true
            displayedID = id
            opacity = 1; offset = 0; switching = false
            return
        }
        switching = true
        withAnimation(.easeIn(duration: 0.12)) {
            opacity = 0
            offset = reduceMotion ? 0 : -14
        }
        do {
            try await Task.sleep(for: .milliseconds(140))
            guard ticket == generation, !Task.isCancelled else { return }
            // No crossfade: old and new composers/transcripts are never mounted together.
            mountedID = nil
            displayedID = id
            offset = reduceMotion ? 0 : 14
            while waitForMount && mountedID != id {
                try await Task.sleep(for: .milliseconds(10))
                guard ticket == generation, !Task.isCancelled else { return }
            }
            // Give the transcript's initial page expansion and deferred bottom positioning
            // a run-loop window while invisible. Slow construction extends this naturally.
            try await Task.sleep(for: .milliseconds(320))
            guard ticket == generation, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { opacity = 1; offset = 0 }
            try await Task.sleep(for: .milliseconds(180))
            guard ticket == generation, !Task.isCancelled else { return }
            switching = false
        } catch {
            // The next task owns presentation. A cancelled older switch must not reveal it.
        }
    }
}

struct ChatSwitchPresentation {
    var opacity = 1.0
    var offset = 0.0
    var switching = false
}
private struct ChatSwitchPresentationKey: EnvironmentKey {
    static let defaultValue = ChatSwitchPresentation()
}
extension EnvironmentValues {
    var chatSwitchPresentation: ChatSwitchPresentation {
        get { self[ChatSwitchPresentationKey.self] }
        set { self[ChatSwitchPresentationKey.self] = newValue }
    }
}
