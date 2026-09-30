import SwiftUI

@main
struct ChatterboxApp: App {
    @State private var model = AppModel()

    private func chatMenuTitle(_ number: Int) -> String {
        let order = model.sidebarOrder
        guard order.indices.contains(number - 1) else { return "Chat \(number)" }
        let session = order[number - 1]
        return session.record.projectFolder != nil ? session.projectName : session.title
    }

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
                Button("New Project\u{2026}") { model.showingNewProject = true }
                    .keyboardShortcut("n", modifiers: [.command, .control])
                Button("Open Project\u{2026}") { model.chooseAndOpenProject() }
                    .keyboardShortcut("o")
                Button("New Project from GitHub\u{2026}") { model.showingCloneFromGitHub = true }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        .commands {
            // ⌘⇧P belongs to the mode menu; there's nothing to print.
            CommandGroup(replacing: .printItem) {}

            CommandMenu("Go") {
                Button("Quick Switcher\u{2026}") { ChatCommands.shared.showingQuickSwitcher.toggle() }
                    .keyboardShortcut("k")
                Divider()
                Button("Next Chat") { model.selectAdjacentChat(1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Chat") { model.selectAdjacentChat(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Divider()
                ForEach(1...9, id: \.self) { number in
                    Button(chatMenuTitle(number)) { model.selectChat(number: number) }
                        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                        .disabled(model.sidebarOrder.count < number)
                }
            }

            CommandMenu("Pins") {
                ForEach(1...9, id: \.self) { number in
                    let pins = PinStore.shared.visiblePins(in: model.selectedPinPlace)
                    Button(pins.indices.contains(number - 1) ? pins[number - 1].title : "Pin \(number)") {
                        PinStore.shared.open(number: number, in: model.selectedPinPlace)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: [.command, .control])
                    .disabled(!pins.indices.contains(number - 1))
                }
            }

            CommandMenu("Chat") {
                Button("Choose Model\u{2026}") { ChatCommands.shared.toggleModelPopover() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Choose Mode\u{2026}") { ChatCommands.shared.toggleModePopover() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Open Terminal Here") { model.openTerminal() }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                    .disabled(model.selected == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
