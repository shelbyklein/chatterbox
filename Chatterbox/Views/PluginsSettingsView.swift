import SwiftUI

/// Settings → Plugins: every plugin Claude Code's catalogs offer, searchable, with what each
/// one adds and costs, and the catalogs themselves. Installs and changes go through Claude
/// Code's own `claude plugin` commands and apply to new Claude chats.
struct PluginsSettingsView: View {
    private let store = ClaudePlugins.shared
    @State private var search = ""
    @State private var showInstalledOnly = false
    @State private var catalog = ""
    @State private var selected: ClaudePlugins.Plugin?
    @State private var showingCatalogs = false

    private var filtered: [ClaudePlugins.Plugin] {
        let words = search.lowercased().split(separator: " ").map(String.init)
        return store.plugins.filter { plugin in
            if showInstalledOnly && plugin.installed == nil { return false }
            if !catalog.isEmpty && plugin.marketplace != catalog { return false }
            let haystack = (plugin.name + " " + plugin.description + " " + plugin.marketplace).lowercased()
            return words.allSatisfy(haystack.contains)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let problem = store.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            list
            Text("Plugins add skills, agents, hooks and MCP servers to Claude Code. Most come from third parties and can run code on this Mac, so install the ones you trust. Changes apply to Claude chats started after them.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .task { await store.refreshIfStale() }
        .sheet(item: $selected) { plugin in PluginDetailSheet(plugin: plugin) }
        .sheet(isPresented: $showingCatalogs) { CatalogsSheet() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            TextField("Search \(store.plugins.count) plugins", text: $search)
                .textFieldStyle(.roundedBorder)
            Picker("Catalog", selection: $catalog) {
                Text("All Catalogs").tag("")
                ForEach(Array(Set(store.plugins.map(\.marketplace))).sorted(), id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Toggle("Installed (\(store.installedCount))", isOn: $showInstalledOnly)
                .toggleStyle(.button)
            Button { showingCatalogs = true } label: { Label("Catalogs", systemImage: "books.vertical") }
                .help("The catalogs Claude Code installs plugins from, and adding more")
            Button { Task { await store.refresh() } } label: {
                if store.isLoading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
            }
            .help("Refresh")
            .disabled(store.isLoading)
        }
    }

    private var list: some View {
        List(filtered) { plugin in
            Button { selected = plugin } label: { PluginRow(plugin: plugin) }
                .buttonStyle(.plain)
        }
        .listStyle(.inset)
        .overlay {
            if store.plugins.isEmpty && store.isLoading {
                ProgressView("Reading Claude Code's catalogs\u{2026}")
            } else if filtered.isEmpty && !store.isLoading {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}

private struct PluginRow: View {
    let plugin: ClaudePlugins.Plugin

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: plugin.installed == nil ? "puzzlepiece.extension" : "puzzlepiece.extension.fill")
                .foregroundStyle(plugin.installed?.enabled == true ? Color.highlight : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(plugin.name).font(.callout.weight(.medium))
                    Text(plugin.marketplace).font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                    if let installed = plugin.installed {
                        Text(installed.enabled ? "Installed" : "Off").font(.caption2.weight(.semibold))
                            .foregroundStyle(installed.enabled ? .green : .secondary)
                    }
                    Spacer()
                    if let count = plugin.installCount {
                        Label(count.formatted(.number.notation(.compactName)), systemImage: "arrow.down.circle")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .help("\(count) installs")
                    }
                }
                if !plugin.description.isEmpty {
                    Text(plugin.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// One plugin: what it is, where it comes from, what it adds and costs, and what you can do.
private struct PluginDetailSheet: View {
    let plugin: ClaudePlugins.Plugin
    private let store = ClaudePlugins.shared
    @Environment(\.dismiss) private var dismiss
    @State private var details: String?
    @State private var confirmingInstall = false

    /// The plugin as the store has it now (its state changes after an install).
    private var current: ClaudePlugins.Plugin { store.plugins.first { $0.id == plugin.id } ?? plugin }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.name).font(.title2.weight(.semibold))
                    Text("\(current.marketplace)\(current.version.map { " \u{00B7} " + $0 } ?? "")")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isBusy(current.id) { ProgressView().controlSize(.small) }
            }
            if !current.description.isEmpty {
                Text(current.description).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if let source = current.source {
                if let url = URL(string: source), url.scheme?.hasPrefix("http") == true {
                    Link(source, destination: url).font(.callout)
                } else {
                    Text(source).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            GroupBox {
                ScrollView {
                    Text(details ?? "Reading what it contains\u{2026}")
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 180, maxHeight: 300)
            } label: {
                Text("What it adds, and its token cost")
            }
            if let problem = store.problem {
                Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let installed = current.installed {
                    Button("Uninstall", role: .destructive) { Task { await store.uninstall(current) } }
                    Button(installed.enabled ? "Turn Off" : "Turn On") { Task { await store.setEnabled(current, !installed.enabled) } }
                    Button("Update") { Task { await store.update(current) } }
                } else {
                    Button("Install\u{2026}") { confirmingInstall = true }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .disabled(store.isBusy(current.id))
        }
        .padding(20)
        .frame(width: 560)
        .task { details = await store.details(plugin) }
        .confirmationDialog("Install \(current.name)?", isPresented: $confirmingInstall) {
            Button("Install for All Claude Chats") { Task { await store.install(current) } }
        } message: {
            Text("It comes from \(current.source ?? current.marketplace). Plugins can add hooks and MCP servers that run on this Mac. New Claude chats load it; open ones pick it up when they restart.")
        }
    }
}

/// The catalogs Claude Code installs plugins from: the ones it has, suggested ones, and any
/// GitHub repo, URL or folder you add.
private struct CatalogsSheet: View {
    private let store = ClaudePlugins.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newSource = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Plugin Catalogs").font(.title2.weight(.semibold))
            Text("Claude Code's built-in Anthropic Directory is always there. Add others to browse their plugins here; adding a catalog installs nothing.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            ForEach(ClaudePlugins.suggested, id: \.source) { suggestion in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(suggestion.name) \u{00B7} \(suggestion.source)").font(.callout.weight(.medium))
                        Text(suggestion.about).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if store.hasMarketplace(suggestion.source) {
                        Label("Added", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                    } else {
                        Button("Add") { Task { await store.addMarketplace(suggestion.source) } }
                            .disabled(store.isBusy(suggestion.source))
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            }

            List(store.marketplaces) { marketplace in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(marketplace.name)
                        Text(marketplace.location).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button { Task { await store.removeMarketplace(marketplace) } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Remove this catalog (plugins installed from it stay until you uninstall them)")
                        .disabled(store.isBusy(marketplace.name))
                }
            }
            .frame(minHeight: 160)

            HStack {
                TextField("owner/repo, a URL, or a folder", text: $newSource)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add Catalog", action: add).disabled(newSource.trimmingCharacters(in: .whitespaces).isEmpty || store.isBusy(newSource))
            }
            if let problem = store.problem {
                Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Update All Catalogs") { Task { await store.updateMarketplaces() } }
                    .disabled(store.isBusy("marketplaces"))
                if store.isBusy("marketplaces") || store.isLoading { ProgressView().controlSize(.small) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 560)
    }

    private func add() {
        let source = newSource
        newSource = ""
        Task { await store.addMarketplace(source) }
    }
}
