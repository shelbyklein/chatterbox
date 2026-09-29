import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Pins section at the top of the sidebar. Click a pin to open it; drop an app, file, or
/// link here to pin it; right-click to rename or remove; drag to reorder.
struct PinsSection: View {
    @Binding var addingPin: Bool
    @State private var renaming: Pin?
    @State private var newTitle = ""
    @State private var dropTargeted = false
    private var store: PinStore { .shared }

    var body: some View {
        Section {
            ForEach(Array(store.pins.enumerated()), id: \.element.id) { index, pin in
                PinRow(pin: pin, number: index < 9 ? index + 1 : nil)
                    .contextMenu {
                        Button("Open") { store.open(pin) }
                        Button("Rename\u{2026}") { newTitle = pin.title; renaming = pin }
                        if pin.kind == .app || pin.kind == .file {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: pin.target)]) }
                        }
                        if pin.kind == .website {
                            Button("Copy Link") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(pin.target, forType: .string)
                            }
                        }
                        Divider()
                        Button("Remove Pin", role: .destructive) { store.remove(pin) }
                    }
                    .draggable(pin.id.uuidString)
                    .dropDestination(for: String.self) { ids, _ in
                        guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
                        store.move(id, to: pin.id)
                        return true
                    }
            }
            if store.pins.isEmpty {
                Text("Pin websites, apps, folders, or Shortcuts you open often. Drop them here, or click +.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Pins")
                Spacer()
                Button { addingPin = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Add a pin")
            }
        }
        .onDrop(of: [.fileURL, .url], isTargeted: $dropTargeted, perform: dropped)
        .alert("Rename Pin", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newTitle)
            Button("Rename") { if let pin = renaming { store.rename(pin, to: newTitle.trimmingCharacters(in: .whitespaces)) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Apps and files pin as themselves; links (say, dragged from a browser) pin as websites.
    private func dropped(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    Task { @MainActor in
                        let isApp = url.pathExtension == "app"
                        PinStore.shared.add(Pin(title: isApp ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent,
                                                kind: isApp ? .app : .file, target: url.path))
                    }
                }
            } else {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, !url.isFileURL else { return }
                    Task { @MainActor in
                        PinStore.shared.add(Pin(title: url.host ?? url.absoluteString, kind: .website, target: url.absoluteString))
                    }
                }
            }
        }
        return true
    }
}

private struct PinRow: View {
    let pin: Pin
    let number: Int?
    private var store: PinStore { .shared }

    var body: some View {
        Button { store.open(pin) } label: {
            HStack(spacing: 7) {
                PinIcon(pin: pin).frame(width: 16, height: 16)
                Text(pin.title).lineLimit(1)
                Spacer(minLength: 0)
                if !store.isAvailable(pin) {
                    Image(systemName: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        .help("\(pin.target) is missing")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(number.map { "\(pin.target)  (\u{2303}\u{2318}\($0))" } ?? pin.target)
    }
}

struct PinIcon: View {
    let pin: Pin

    var body: some View {
        if let image = PinStore.shared.icon(for: pin) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: pin.kind == .shortcut ? "square.stack.3d.up.fill" : pin.kind == .website ? "globe" : "doc")
                .foregroundStyle(.secondary)
        }
    }
}

/// Adding a pin: pick the kind, then a site, app, file, or Shortcut. Apps you likely want
/// (those not yet pinned) are suggested.
struct AddPinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Pin.Kind = .website
    @State private var title = ""
    @State private var url = ""
    @State private var appQuery = ""
    @State private var apps: [URL] = []
    @State private var shortcuts: [String] = []
    @State private var loadedShortcuts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Pin").font(.title3.weight(.semibold))
            Picker("Kind", selection: $kind) {
                ForEach(Pin.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch kind {
                case .website: websiteForm
                case .app: appList
                case .file: fileChooser
                case .shortcut: shortcutList
                }
            }
            .frame(height: 280, alignment: .top)

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { apps = PinStore.installedApps() }
        .task(id: kind) {
            if kind == .shortcut, !loadedShortcuts {
                shortcuts = await PinStore.shortcutNames()
                loadedShortcuts = true
            }
        }
    }

    private var websiteForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Address, e.g. localhost:3000 or ontarget.com", text: $url).textFieldStyle(.roundedBorder)
            TextField("Name (optional)", text: $title).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Add Pin") {
                    guard let link = PinStore.normalizedURL(url) else { return }
                    let name = title.trimmingCharacters(in: .whitespaces)
                    PinStore.shared.add(Pin(title: name.isEmpty ? (link.host ?? link.absoluteString) : name, kind: .website, target: link.absoluteString))
                    url = ""
                    title = ""
                }
                .keyboardShortcut(.defaultAction)
                .disabled(PinStore.normalizedURL(url) == nil)
            }
        }
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search apps", text: $appQuery).textFieldStyle(.roundedBorder)
            List {
                ForEach(filteredApps, id: \.self) { app in
                    let pinned = PinStore.shared.pins.contains { $0.kind == .app && $0.target == app.path }
                    Button {
                        PinStore.shared.add(Pin(title: app.deletingPathExtension().lastPathComponent, kind: .app, target: app.path))
                    } label: {
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 18, height: 18)
                            Text(app.deletingPathExtension().lastPathComponent)
                            Spacer()
                            if pinned { Image(systemName: "pin.fill").foregroundStyle(Color.highlight) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(pinned)
                }
            }
        }
    }

    /// Apps matching the search, with your own projects' apps (in ~/Applications) first.
    private var filteredApps: [URL] {
        let q = appQuery.trimmingCharacters(in: .whitespaces)
        let matched = q.isEmpty ? apps : apps.filter { $0.deletingPathExtension().lastPathComponent.localizedStandardContains(q) }
        let home = NSHomeDirectory() + "/Applications"
        return matched.filter { $0.path.hasPrefix(home) } + matched.filter { !$0.path.hasPrefix(home) }
    }

    private var fileChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pin a file or folder: a project folder, a document, a log.").foregroundStyle(.secondary)
            Button("Choose\u{2026}") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = true
                panel.prompt = "Pin"
                guard panel.runModal() == .OK else { return }
                for url in panel.urls {
                    PinStore.shared.add(Pin(title: url.lastPathComponent, kind: url.pathExtension == "app" ? .app : .file, target: url.path))
                }
            }
        }
    }

    private var shortcutList: some View {
        Group {
            if !loadedShortcuts {
                ProgressView().frame(maxWidth: .infinity)
            } else if shortcuts.isEmpty {
                Text("No Shortcuts found. Make one in the Shortcuts app, then come back.").foregroundStyle(.secondary)
            } else {
                List(shortcuts, id: \.self) { name in
                    let pinned = PinStore.shared.pins.contains { $0.kind == .shortcut && $0.target == name }
                    Button { PinStore.shared.add(Pin(title: name, kind: .shortcut, target: name)) } label: {
                        HStack {
                            Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.secondary)
                            Text(name)
                            Spacer()
                            if pinned { Image(systemName: "pin.fill").foregroundStyle(Color.highlight) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(pinned)
                }
            }
        }
    }
}
