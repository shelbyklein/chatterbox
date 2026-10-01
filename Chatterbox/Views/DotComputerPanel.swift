import SwiftUI
import WebKit

/// Beside Dot's chat: its computer's screen, live. Click and type in it to take over (to sign
/// in somewhere, say). Set it up the first time, then start and stop it here.
struct DotComputerPanel: View {
    @Environment(AppModel.self) private var model
    private var computer: DotComputer { .shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                Text("Dot's Computer").font(.headline)
                statusLabel
                Spacer()
                actions
                Button { model.showingDotComputer = false } label: { Image(systemName: "sidebar.trailing") }
                    .buttonStyle(.borderless)
                    .help("Hide the computer")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            Divider()
            content
        }
        .task { await computer.refresh() }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch computer.state {
        case .running: Label("Running", systemImage: "circle.fill").labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.green)
        case .building, .starting: ProgressView().controlSize(.small)
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch computer.state {
        case .running:
            Button("Stop") { Task { await model.stopDotComputer() } }
        case .stopped, .failed:
            Button("Start") { Task { await model.startDotComputer() } }.buttonStyle(.borderedProminent)
        case .notSetUp:
            Button("Set Up") { Task { await model.setUpDotComputer() } }.buttonStyle(.borderedProminent)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch computer.state {
        case .running:
            LiveScreen(url: computer.viewURL)
        case .building, .starting:
            message("desktopcomputer", computer.progress.isEmpty ? "Starting\u{2026}" : computer.progress)
        case .notSetUp:
            message("desktopcomputer.and.arrow.down",
                    "Dot can have its own computer: a small Linux machine with a web browser, separate from your Mac. It browses, reads pages, and fills in forms there while you watch, and you can take over to sign in.\n\nSetting it up downloads about 2.4 GB with Docker, once.")
        case .noDocker:
            message("shippingbox", "Dot's computer runs with Docker. Install Docker Desktop, then come back.")
        case .stopped:
            message("power", "The computer is off. Start it to let Dot browse; its logins are kept from last time.")
        case .failed(let reason):
            message("exclamationmark.triangle", reason)
        case .checking:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func message(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(.secondary)
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 360)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The computer's screen through noVNC: live, and clickable to take over.
private struct LiveScreen: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}
}
