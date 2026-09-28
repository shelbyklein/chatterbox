import SwiftUI

@main
struct ChatterboxApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { model.newChat() }
                    .keyboardShortcut("n")
                Button("New Claude Chat") { model.newChat(backend: .claude) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("New Codex Chat") { model.newChat(backend: .codex) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Open Project\u{2026}") { model.chooseAndOpenProject() }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
