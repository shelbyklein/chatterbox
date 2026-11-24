import AppKit
import ApplicationServices
import Foundation

/// Outlook's Inbox message list through the Mac's accessibility features (the new Outlook
/// has no scripting). Run by Chatterbox Host (`--read-outlook DOMAIN`), which has the
/// Accessibility permission; the always-on Desk's MailWatcher parses the rows.
/// Reads only a main window that isn't searching, with the Inbox selected, and only the
/// rows Outlook has drawn (always the newest). Changes nothing in Outlook.
enum OutlookAX {
    struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }
    static let bundleID = "com.microsoft.Outlook"

    /// For the host: prints {"rows": […]} or {"error": "…"} as one line.
    static func printInbox(domain: String) {
        var answer: [String: Any]
        do { answer = ["rows": try readInbox(domain: domain)] }
        catch let failure as Failure { answer = ["error": failure.message] }
        catch { answer = ["error": "\(error)"] }
        let data = (try? JSONSerialization.data(withJSONObject: answer)) ?? Data("{}".utf8)
        print(String(decoding: data, as: UTF8.self))
    }

    /// The Inbox list's rows, top first. Throws a readable reason when it can't read them.
    static func readInbox(domain: String) throws -> [String] {
        guard AXIsProcessTrusted() else {
            askForAccess()
            throw Failure("Allow Chatterbox Host in System Settings → Privacy & Security → Accessibility, so the Desk can read Outlook.")
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            throw Failure("Open Outlook (or add your \(domain) account to Apple Mail) so the Desk can see new mail.")
        }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 5)
        var list: AnyObject?
        let status = AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &list)
        guard status == .success else {
            throw Failure("Couldn't read Outlook's windows (accessibility error \(status.rawValue)); check Chatterbox Host is allowed under Privacy & Security → Accessibility.")
        }
        let windows = (list as? [AXUIElement]) ?? []
        // A window that isn't searching and shows the Inbox.
        var seen: [String] = []
        let inboxes = windows.filter { window in
            let title = (value(window, kAXTitleAttribute) as? String) ?? ""
            var budget = 3000
            let folders = find(in: window, budget: &budget, where: { (value($0, kAXRoleAttribute) as? String) == kAXOutlineRole })
            let selected = folders.map { (value($0, kAXSelectedRowsAttribute) as? [AXUIElement]) ?? [] } ?? []
            let names = selected.map { row in
                let cell = ((value(row, kAXChildrenAttribute) as? [AXUIElement]) ?? []).first ?? row
                return (value(cell, kAXDescriptionAttribute) as? String) ?? ""
            }
            seen.append("\u{201C}\(title)\u{201D}" + (folders == nil ? "" : " on \(names.first.map { $0.components(separatedBy: ";").first ?? $0 } ?? "no folder")"))
            guard !title.hasPrefix("Searching") else { return false }
            // Its title ("Inbox • you@usarchery.org"), or the Inbox selected in its folder list.
            return (title.hasPrefix("Inbox") && title.localizedCaseInsensitiveContains("@" + domain)) || names.contains { $0.hasPrefix("Inbox") }
        }
        guard let window = inboxes.first else {
            throw Failure("Outlook isn't showing the \(domain) Inbox; the Desk reads mail when it is. Its windows: \(seen.isEmpty ? "none" : seen.joined(separator: ", ")).")
        }
        var budget = 4000
        guard let table = find(in: window, budget: &budget, where: {
            (value($0, kAXRoleAttribute) as? String) == kAXTableRole && (value($0, kAXDescriptionAttribute) as? String) == "Message List"
        }) else { throw Failure("Couldn't find Outlook's message list.") }
        let rows = (value(table, kAXRowsAttribute) as? [AXUIElement]) ?? (value(table, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        return rows.prefix(200).compactMap { row in
            let cell = ((value(row, kAXChildrenAttribute) as? [AXUIElement]) ?? []).first ?? row
            return (value(cell, kAXDescriptionAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// Asks macOS once per launch to list the service under Accessibility.
    nonisolated(unsafe) private static var asked = false
    private static func askForAccess() {
        guard !asked else { return }
        asked = true
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var result: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    private static func find(in element: AXUIElement, budget: inout Int, where match: (AXUIElement) -> Bool) -> AXUIElement? {
        guard budget > 0 else { return nil }
        budget -= 1
        if match(element) { return element }
        // The folder list and toolbar are never the message list: don't descend into rows or cells.
        let role = value(element, kAXRoleAttribute) as? String
        // Nor into text fields: Outlook's search field nests copies of itself many levels deep.
        guard role != kAXRowRole, role != kAXCellRole, role != kAXTextFieldRole else { return nil }
        for child in (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            if let found = find(in: child, budget: &budget, where: match) { return found }
        }
        return nil
    }
}
