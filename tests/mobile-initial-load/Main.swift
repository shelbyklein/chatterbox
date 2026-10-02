import SwiftUI
@main struct RegressionApp: App {
    @State private var store = MobileStore()
    @State private var history = MobileChatHistory(id: UUID(uuidString:"11111111-1111-1111-1111-111111111111")!)
    private let chat = Companion.ChatSummary(id: UUID(uuidString:"11111111-1111-1111-1111-111111111111")!, title:"Golem", backend:"codex", isRunning:false, isWaitingOnYou:false, updatedAt:Date(), isDot:true)
    var body: some Scene {
        WindowGroup {
            Group {
                if store.isPaired { NavigationStack { ChatDetailView(chat:chat, history:history) } }
                else { Text("Pairing test server") }
            }
            .environment(store)
            .environment(\.readerStyle, .mobile)
            // Reproduce entering a detail while its navigation scene is inactive.
            .environment(\.scenePhase, .inactive)
            .task {
                if !store.isPaired { try? await store.pair(host:"127.0.0.1",code:"123456") }
                await history.refresh(in: store, force: true).value
            }
        }
    }
}
extension ReaderStyle { static var mobile: ReaderStyle { var s=ReaderStyle.defaults; s.textSize=17; s.contentWidth=10000;return s } }
