import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selectedID) {
                let projects = model.sessions.filter { $0.record.projectFolder != nil }
                    .sorted { $0.projectName.localizedStandardCompare($1.projectName) == .orderedAscending }
                let chats = model.sessions.filter { $0.record.projectFolder == nil }
                if !projects.isEmpty {
                    Section("Projects") {
                        ForEach(projects) { session in row(session) }
                    }
                }
                Section(projects.isEmpty ? "" : "Chats") {
                    ForEach(chats) { session in row(session) }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("New Claude Chat") { model.newChat(backend: .claude) }
                        Button("New Codex Chat") { model.newChat(backend: .codex) }
                        Divider()
                        Button("New Project Chat\u{2026}") { model.chooseAndOpenProject() }
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    } primaryAction: {
                        model.newChat()
                    }
                    .help("New chat (\u{2318}N). Hold to pick Claude, Codex, or a project folder.")
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

extension ContentView {
    private func row(_ session: ChatSession) -> some View {
        SidebarRow(session: session)
            .tag(session.id)
            .contextMenu {
                if let folder = session.record.projectFolder {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
                    Button("Unbind from Folder") { session.unbindProject() }
                    Divider()
                }
                Button("Delete Chat", role: .destructive) { model.delete(session) }
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
            if session.record.projectFolder != nil {
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.projectName).lineLimit(1)
                    if session.title != "New chat" {
                        Text(session.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .help(session.record.projectFolder ?? "")
            } else {
                Text(session.title)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if session.isRunning {
                ProgressView().controlSize(.mini)
            }
        }
    }
}
