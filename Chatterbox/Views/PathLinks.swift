import AppKit
import SwiftUI

/// Paths an agent writes as code (`/Users/…/final/`, `svg/`, `logo.png`) become links that
/// show the file in Finder. A relative path is looked for in the folders the same reply
/// names, then in the chat's folder. Only paths that exist are linked, so ordinary code
/// like `record.items` stays plain.
struct PathLinks {
    static let scheme = "chatterbox-reveal"

    /// Folders to look in for relative paths, most specific first.
    var bases: [String]

    /// The folders a reply names in code, then the chat's folder.
    static func context(for text: String, folder: String?) -> PathLinks {
        var bases: [String] = []
        let fm = FileManager.default
        for code in codeSpans(in: text) where code.hasPrefix("/") || code.hasPrefix("~") {
            let path = (code as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            let base = isDirectory.boolValue ? path : (path as NSString).deletingLastPathComponent
            if !bases.contains(base) { bases.append(base) }
        }
        if let folder, !bases.contains(folder) { bases.append(folder) }
        return PathLinks(bases: bases)
    }

    /// A link for `code` if it names a file or folder that exists.
    func url(for code: String) -> URL? {
        let text = code.trimmingCharacters(in: .whitespaces)
        guard Self.looksLikePath(text), let path = resolve(text) else { return nil }
        var components = URLComponents()
        components.scheme = Self.scheme
        components.path = path
        return components.url
    }

    private func resolve(_ text: String) -> String? {
        let fm = FileManager.default
        let candidates: [String]
        if text.hasPrefix("/") || text.hasPrefix("~") {
            candidates = [(text as NSString).expandingTildeInPath]
        } else {
            candidates = bases.map { ($0 as NSString).appendingPathComponent(text) }
        }
        for candidate in candidates {
            if fm.fileExists(atPath: candidate) { return candidate }
            // "file.swift:42" names a line in the file.
            if let range = candidate.range(of: #":\d+(:\d+)?$"#, options: .regularExpression) {
                let trimmed = String(candidate[..<range.lowerBound])
                if fm.fileExists(atPath: trimmed) { return trimmed }
            }
        }
        return nil
    }

    /// Something shaped like a path or a file name, before checking the disk.
    private static func looksLikePath(_ text: String) -> Bool {
        guard !text.isEmpty, text.count < 1024, !text.contains("\n"), !text.contains("://") else { return false }
        if text.hasPrefix("/") || text.hasPrefix("~/") || text.hasPrefix("./") || text.hasPrefix("../") { return true }
        if text.contains(" ") { return false }
        return text.contains("/") || text.range(of: #"^[\w@+\-.]+\.[A-Za-z][A-Za-z0-9]{0,5}$"#, options: .regularExpression) != nil
    }

    private static func codeSpans(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "`([^`\n]+)`") else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }
    }

    /// Opens a folder in Finder, or shows a file selected in its folder.
    static func reveal(_ url: URL) {
        let path = url.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return NSSound.beep() }
        let file = URL(fileURLWithPath: path)
        if isDirectory.boolValue, file.pathExtension != "app" {
            NSWorkspace.shared.open(file)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
    }
}

private struct ChatFolderKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The folder the chat works in, for resolving paths in its replies.
    var chatFolder: String? {
        get { self[ChatFolderKey.self] }
        set { self[ChatFolderKey.self] = newValue }
    }
}
