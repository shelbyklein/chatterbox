import SwiftUI
import WidgetKit

@main
struct WidgetPreviewApp: App {
    @State private var openedLink = ""
    @AppStorage(WidgetChatShortcut.selectionKey, store: WidgetChatShortcut.preferences)
    private var selectedProvider = WidgetChatShortcut.codex.rawValue

    init() {
        if ProcessInfo.processInfo.environment["WIDGET_RESET_SELECTION"] == "1" {
            WidgetChatShortcut.preferences.removeObject(forKey: WidgetChatShortcut.selectionKey)
        }
    }
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var family: WidgetFamily {
        switch environment["WIDGET_SIZE"] {
        case "small": .systemSmall
        case "large": .systemLarge
        default: .systemMedium
        }
    }
    private var size: CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemLarge: CGSize(width: 364, height: 382)
        default: CGSize(width: 364, height: 170)
        }
    }
    private var snapshot: WidgetSnapshot {
        var result = WidgetSnapshot.sample
        let mode = environment["WIDGET_STATE"] ?? "current"
        if environment["WIDGET_KIND"] == "usage", mode != "legacy" {
            result.usage?.claude = [] // Proxy quotas must work without Claude chat-process events.
        }
        if mode == "empty" { result = .empty }
        if mode == "working-only" {
            result.waiting = []; result.newReplies = []
            result.working = [.init(chatID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, title: "Playcase Arcade", detail: nil, backend: "claude", date: .now)]
        }
        if mode == "stale" {
            result.updatedAt = .now.addingTimeInterval(-7200)
            result.usage?.syncedAt = result.updatedAt
            result.usage?.proxyChecked = result.updatedAt
        }
        if mode == "legacy" {
            result.usage?.proxyAccounts = nil
            result.usage?.proxyChecked = nil
            result.usage?.proxyRefreshing = nil
        }
        if mode == "checking" {
            result.usage?.claude = []; result.usage?.codex = []
            result.usage?.proxyAccounts = []
            result.usage?.proxyChecked = nil
            result.usage?.proxyRefreshing = true
        }
        if mode == "overflow" {
            result.usage?.proxyAccounts = (0..<24).map { index in
                .init(provider: index % 2 == 0 ? "claude" : "codex", name: "Long account name \(index + 1)", status: "Available",
                      windows: [.init(label: "5-hour window", fraction: 0.4, resetsAt: nil),
                                .init(label: "7-day Sonnet", fraction: 0.9, resetsAt: nil),
                                .init(label: "Code review · Weekly limit", fraction: 0.2, resetsAt: nil)])
            }
        }
        if mode == "boundaries" {
            result.usage?.claude = [.init(label: "5-hour", fraction: 0, resetsAt: nil), .init(label: "7-day", fraction: 1, resetsAt: nil)]
            result.usage?.codex = [.init(label: "5-hour", fraction: nil, resetsAt: nil), .init(label: "7-day", fraction: 0.7, resetsAt: .now.addingTimeInterval(-60))]
            result.waiting[0].title = "A longer thread title to check the compact widget"
        }
        return result
    }
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 24) {
                Text("Native widget fixture").font(.headline)
                Group {
                    if environment["WIDGET_KIND"] == "new-chat" {
                        ChatterboxNewChatWidgetView(selection: WidgetChatShortcut(rawValue: selectedProvider) ?? .codex, family: family)
                    } else if environment["WIDGET_KIND"] == "usage" {
                        ChatterboxUsageWidgetView(entry: SnapshotEntry(date: .now, snapshot: snapshot), family: family)
                    } else {
                        ChatterboxWidgetView(entry: SnapshotEntry(date: .now, snapshot: snapshot), family: family)
                    }
                }
                    .padding(16)
                    .frame(width: size.width, height: size.height)
                    .background(.tertiary, in: RoundedRectangle(cornerRadius: 22))
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("widget-preview")
                Text(openedLink).font(.caption).accessibilityIdentifier("opened-widget-link")
            }
            .environment(\.openURL, OpenURLAction { url in openedLink = url.absoluteString; return .handled })
            .environment(\.dynamicTypeSize, environment["WIDGET_LARGE_TEXT"] == "1" ? .xxxLarge : .large)
            .preferredColorScheme(environment["WIDGET_LIGHT"] == "1" ? .light : .dark)
        }
    }
}
