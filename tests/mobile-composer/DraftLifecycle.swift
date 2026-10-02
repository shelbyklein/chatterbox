import Foundation
@main struct DraftLifecycle {
    @MainActor static func main() {
        var persisted = ""
        var persistedImages: [Int] = []
        let state = MobileComposerDraft<Int>(text: "  Sent text  ", images: [1],
            persistText: { persisted = $0 }, persistImages: { persistedImages = $0 })
        let dictationGeneration = state.inputGeneration
        let sent = state.beginSend()!
        precondition(state.text.isEmpty && state.images.isEmpty && persisted.isEmpty && persistedImages.isEmpty)
        precondition(state.beginSend() == nil, "Another presentation submitted concurrently")
        state.applyTranscription("Late final result", prefix: "Old draft", generation: dictationGeneration)
        precondition(state.text.isEmpty, "Late speech callback restored a submitted draft")
        state.text = "New draft"
        state.images.append(2)
        state.finish(sent)
        precondition(state.text == "New draft" && persisted == "New draft" && state.images == [2] && persistedImages == [2])
        state.applyTranscription("Late final result", prefix: "Old draft", generation: dictationGeneration)
        precondition(state.text == "New draft", "Late speech callback replaced new typing after acknowledgment")
        let rejected = state.beginSend()!
        state.text = "Typed during failure"
        state.images = [3]
        state.finish(rejected, failed: true)
        precondition(state.text == "New draft\n\nTyped during failure" && state.images == [2,3])
        state.finish(sent, failed: true)
        precondition(state.text == "New draft\n\nTyped during failure", "Stale completion rewrote the draft")
        state.text = "Repeated intentional text"
        state.images = []
        let repeat1 = state.beginSend()!
        state.finish(repeat1)
        state.text = "Repeated intentional text"
        let repeat2 = state.beginSend()!
        precondition(repeat1.id != repeat2.id && repeat1.text == repeat2.text)
        state.finish(repeat2, failed: true)
        precondition(state.text == repeat2.text && !state.sending)
        print("PASS consume/persist, in-flight guard, new text/images, failure recovery, stale completion and speech, intentional repeat")
    }
}
