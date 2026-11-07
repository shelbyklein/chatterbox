import SwiftUI
import WidgetKit

@main
struct WidgetPreviewApp: App {
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
        if mode == "empty" { result = .empty }
        if mode == "stale" {
            result.updatedAt = .now.addingTimeInterval(-7200)
            result.usage?.syncedAt = result.updatedAt
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
                ChatterboxWidgetView(entry: SnapshotEntry(date: .now, snapshot: snapshot), family: family)
                    .padding(16)
                    .frame(width: size.width, height: size.height)
                    .background(.tertiary, in: RoundedRectangle(cornerRadius: 22))
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("widget-preview")
            }
            .preferredColorScheme(environment["WIDGET_LIGHT"] == "1" ? .light : .dark)
        }
    }
}
