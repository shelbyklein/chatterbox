import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selectedID) {
                ForEach(model.sessions) { session in
                    SidebarRow(session: session)
                        .tag(session.id)
                        .contextMenu {
                            Button("Delete Chat", role: .destructive) { model.delete(session) }
                        }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("New Claude Chat") { model.newChat(backend: .claude) }
                        Button("New Codex Chat") { model.newChat(backend: .codex) }
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    } primaryAction: {
                        model.newChat()
                    }
                    .help("New chat (\u{2318}N). Hold to pick Claude or Codex.")
                }
            }
        } detail: {
            if let session = model.selected {
                ChatView(session: session)
                    .id(session.id)
            } else {
                Text("No chat selected").foregroundStyle(.secondary)
            }
        }
    }
}

private struct SidebarRow: View {
    let session: ChatSession

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: session.record.backend == .codex ? "terminal" : "sparkle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(session.record.backend.label)
            Text(session.title)
                .lineLimit(1)
            Spacer(minLength: 0)
            if session.isRunning {
                ProgressView().controlSize(.mini)
            }
        }
    }
}
