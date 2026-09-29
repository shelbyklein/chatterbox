import AppKit
import Observation

/// Something you open often: a website, an app, a file or folder, or a macOS Shortcut.
/// Shown at the top of the sidebar; the first nine open with ⌃⌘1–⌃⌘9.
struct Pin: Codable, Identifiable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case website, app, file, shortcut

        var label: String {
            switch self {
            case .website: "Website"
            case .app: "App"
            case .file: "File or Folder"
            case .shortcut: "Shortcut"
            }
        }
    }

    var id = UUID()
    var title: String
    var kind: Kind
    /// A URL, an app or file path, or a Shortcut's name.
    var target: String
}

@MainActor
@Observable
final class PinStore {
    static let shared = PinStore()

    private(set) var pins: [Pin]
    /// Favicons for website pins, fetched from the site itself.
    private(set) var favicons: [String: NSImage] = [:]
    @ObservationIgnored private var loadingFavicons: Set<String> = []
    private let key = "pins"

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([Pin].self, from: data) {
            pins = saved
        } else {
            pins = []
        }
    }

    func add(_ pin: Pin) {
        guard !pins.contains(where: { $0.kind == pin.kind && $0.target == pin.target }) else { return }
        pins.append(pin)
        save()
    }

    func remove(_ pin: Pin) {
        pins.removeAll { $0.id == pin.id }
        save()
    }

    func rename(_ pin: Pin, to title: String) {
        guard let index = pins.firstIndex(where: { $0.id == pin.id }), !title.isEmpty else { return }
        pins[index].title = title
        save()
    }

    /// Moves a pin to where `target` is, for drag-to-reorder.
    func move(_ id: UUID, to target: UUID) {
        guard id != target, let from = pins.firstIndex(where: { $0.id == id }),
              let to = pins.firstIndex(where: { $0.id == target }) else { return }
        pins.insert(pins.remove(at: from), at: to)
        save()
    }

    func open(_ pin: Pin) {
        switch pin.kind {
        case .website:
            if let url = Self.normalizedURL(pin.target) { NSWorkspace.shared.open(url) }
        case .app:
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: pin.target), configuration: NSWorkspace.OpenConfiguration())
        case .file:
            NSWorkspace.shared.open(URL(fileURLWithPath: pin.target))
        case .shortcut:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", pin.target]
            try? process.run()
        }
    }

    func open(number: Int) {
        guard pins.indices.contains(number - 1) else { return }
        open(pins[number - 1])
    }

    /// Adds "https://" when a URL was typed without a scheme.
    static func normalizedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") { return URL(string: trimmed) }
        let local = trimmed.hasPrefix("localhost") || trimmed.hasPrefix("127.0.0.1")
        return URL(string: (local ? "http://" : "https://") + trimmed)
    }

    /// Whether a pin's target still exists (apps and files can move or be deleted).
    func isAvailable(_ pin: Pin) -> Bool {
        switch pin.kind {
        case .app, .file: FileManager.default.fileExists(atPath: pin.target)
        case .website, .shortcut: true
        }
    }

    // MARK: - Icons

    func icon(for pin: Pin) -> NSImage? {
        switch pin.kind {
        case .app, .file:
            return FileManager.default.fileExists(atPath: pin.target) ? NSWorkspace.shared.icon(forFile: pin.target) : nil
        case .website:
            guard let host = Self.normalizedURL(pin.target)?.host else { return nil }
            if let image = favicons[host] { return image }
            loadFavicon(for: pin.target, host: host)
            return nil
        case .shortcut:
            return nil
        }
    }

    private func loadFavicon(for target: String, host: String) {
        guard !loadingFavicons.contains(host), let url = Self.normalizedURL(target),
              let scheme = url.scheme, let favicon = URL(string: "\(scheme)://\(url.host ?? host)\(url.port.map { ":\($0)" } ?? "")/favicon.ico") else { return }
        loadingFavicons.insert(host)
        Task {
            var request = URLRequest(url: favicon)
            request.timeoutInterval = 5
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) else { return }
            favicons[host] = image
        }
    }

    // MARK: - Suggestions

    /// Apps in /Applications and ~/Applications, for the add sheet.
    static func installedApps() -> [URL] {
        let fm = FileManager.default
        let folders = ["/Applications", "/Applications/Utilities", "\(NSHomeDirectory())/Applications", "/System/Applications"]
        let apps = folders.flatMap { folder in
            ((try? fm.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".app") }
                .map { URL(fileURLWithPath: folder).appendingPathComponent($0) }
        }
        return apps.sorted { $0.deletingPathExtension().lastPathComponent.localizedStandardCompare($1.deletingPathExtension().lastPathComponent) == .orderedAscending }
    }

    /// Your macOS Shortcuts, from the `shortcuts` command.
    static func shortcutNames() async -> [String] {
        let result = await Git.run("/usr/bin/shortcuts", ["list"])
        guard result.status == 0 else { return [] }
        return result.out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pins) { UserDefaults.standard.set(data, forKey: key) }
    }
}
