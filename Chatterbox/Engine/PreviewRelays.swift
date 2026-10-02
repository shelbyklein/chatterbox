import Foundation
import Network
import Observation

/// Local previews (SKD Studio sites and other dev servers on this Mac) that the agent
/// computer's browser may open, one port at a time, only when you turn them on.
///
/// The computer reaches the Mac's IPv4 loopback through Docker (host.docker.internal), but
/// SKD Studio listens on IPv6 loopback ([::1]) only. For each enabled port Chatterbox runs a
/// relay on 127.0.0.1:PORT → [::1]:PORT, and the computer runs a forwarder on its own
/// localhost:PORT, so pages load at the same http://localhost:PORT address WordPress expects.
/// Nothing listens on the network; ports you haven't enabled aren't reachable.
@MainActor
@Observable
final class PreviewRelays {
    static let shared = PreviewRelays()
    static let key = "computerPreviewPorts"

    struct LocalSite: Identifiable, Hashable {
        var id: Int { port }
        var port: Int
        var title: String
        var process: String
    }

    private(set) var enabled: Set<Int> = Set((UserDefaults.standard.array(forKey: key) as? [Int]) ?? [])
    private(set) var sites: [LocalSite] = []
    private(set) var scanning = false
    @ObservationIgnored private var listeners: [Int: NWListener] = [:]

    func start() {
        for port in enabled { openRelay(port) }
    }

    func setEnabled(_ port: Int, _ on: Bool) {
        if on { enabled.insert(port) } else { enabled.remove(port) }
        UserDefaults.standard.set(Array(enabled).sorted(), forKey: Self.key)
        if on { openRelay(port) } else { listeners[port]?.cancel(); listeners[port] = nil }
        Task {
            if on { await DotComputer.shared.forward(port: port) } else { await DotComputer.shared.unforward(port: port) }
        }
    }

    /// After the computer starts: its forwarders for every enabled port.
    func applyToComputer() async {
        for port in enabled { await DotComputer.shared.forward(port: port) }
    }

    // MARK: - The relay on the Mac

    private func openRelay(_ port: Int) {
        guard listeners[port] == nil, let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
        parameters.allowLocalEndpointReuse = true
        // The site may already answer on IPv4 loopback itself; then Docker reaches it directly
        // and this listener fails to bind, which is fine.
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { client in Self.relay(client, to: nwPort) }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { Task { @MainActor in self?.listeners[port] = nil } }
        }
        listener.start(queue: .global(qos: .userInitiated))
        listeners[port] = listener
    }

    nonisolated private static func relay(_ client: NWConnection, to port: NWEndpoint.Port) {
        let upstream = NWConnection(host: "::1", port: port, using: .tcp)
        let queue = DispatchQueue(label: "chatterbox.preview-relay")
        func pump(_ from: NWConnection, _ to: NWConnection) {
            from.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, error in
                if let data, !data.isEmpty {
                    to.send(content: data, completion: .contentProcessed { _ in pump(from, to) })
                } else if done || error != nil {
                    to.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
                    from.cancel()
                } else {
                    pump(from, to)
                }
            }
        }
        upstream.stateUpdateHandler = { state in
            switch state {
            case .ready: pump(client, upstream); pump(upstream, client)
            case .failed, .cancelled: client.cancel()
            default: break
            }
        }
        client.stateUpdateHandler = { state in if case .failed = state { upstream.cancel() } }
        client.start(queue: queue)
        upstream.start(queue: queue)
    }

    // MARK: - Finding local sites

    /// Web servers listening on this Mac's loopback, with their page titles.
    func scan() async {
        scanning = true
        defer { scanning = false }
        let lsof = await Git.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"])
        var found: [Int: String] = [:]
        for line in lsof.out.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9, let address = parts.last.map(String.init),
                  address.hasPrefix("127.0.0.1:") || address.hasPrefix("[::1]:") || address.hasPrefix("localhost:"),
                  let port = Int(address.split(separator: ":").last ?? ""), port >= 1024,
                  !String(parts[0]).hasPrefix("Chatterbo"), !String(parts[0]).hasPrefix("com.docke") else { continue }
            found[port] = String(parts[0])
        }
        var result: [LocalSite] = []
        for (port, process) in found.sorted(by: { $0.key < $1.key }) {
            guard let title = await Self.title(port) else { continue }   // Not a web page.
            result.append(LocalSite(port: port, title: title, process: process))
        }
        sites = result
    }

    nonisolated private static func title(_ port: Int) async -> String? {
        guard let url = URL(string: "http://localhost:\(port)/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("html") else { return nil }
        let html = String(decoding: data.prefix(200_000), as: UTF8.self)
        guard let start = html.range(of: "<title>", options: .caseInsensitive),
              let end = html.range(of: "</title>", options: .caseInsensitive, range: start.upperBound..<html.endIndex) else {
            return "localhost:\(port)"
        }
        let title = html[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "localhost:\(port)" : title.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#8211;", with: "–")
    }
}
