import CryptoKit
import Foundation
import Network
import Observation

/// Serves the Chatterbox iPhone app: the chat list, each chat's transcript, and sending
/// messages. It answers only the home network and Tailscale, only phones paired with the
/// code shown in Settings, and only while it's turned on there. It runs while Chatterbox is open.
@MainActor
@Observable
final class CompanionServer {
    static let shared = CompanionServer()

    struct Device: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        /// SHA-256 of the phone's token; the token itself isn't kept.
        var tokenHash: String
        var pairedAt = Date()
        var lastSeen: Date?
    }

    static let enabledKey = "companionEnabled"
    private static let devicesKey = "companionDevices"

    private(set) var isRunning = false
    private(set) var problem: String?
    private(set) var devices: [Device] = []
    /// The code a phone enters to pair. A new one comes after each pairing and after
    /// too many wrong tries.
    private(set) var pairingCode = CompanionServer.newCode()

    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var failedPairings = 0

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.devicesKey),
           let saved = try? JSONDecoder().decode([Device].self, from: data) {
            devices = saved
        }
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        on ? start() : stop()
    }

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Companion.port)!)
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "Chatterbox", type: Companion.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            problem = "Couldn't start: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    func newPairingCode() { pairingCode = Self.newCode(); failedPairings = 0 }

    func forget(_ device: Device) {
        devices.removeAll { $0.id == device.id }
        saveDevices()
    }

    /// Where a phone can reach this Mac: its home-network and Tailscale addresses.
    static var addresses: [String] {
        var result: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = pointer.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if ip != "127.0.0.1", allowed(ipv4: ip) { result.append(ip) }
        }
        // Tailscale (100.64.0.0/10) first: it works away from home too.
        return result.sorted { isTailscale($0) && !isTailscale($1) }
    }

    static func isTailscale(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }

    // MARK: - Connections

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            problem = nil
        case .failed(let error):
            isRunning = false
            problem = "Stopped: \(error.localizedDescription)"
            listener = nil
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard Self.isAllowed(connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    /// Reads one request (headers, then a body up to its Content-Length), answers it, and closes.
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return connection.cancel() }
                var buffer = buffer
                if let data { buffer.append(data) }
                if buffer.count > 2_000_000 || error != nil { return connection.cancel() }
                if let request = HTTPRequest(buffer) {
                    let response = self.respond(to: request)
                    connection.send(content: response.data, completion: .contentProcessed { _ in connection.cancel() })
                } else if isComplete {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    // MARK: - Routes

    private func respond(to request: HTTPRequest) -> HTTPResponse {
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.first == "v1" else { return .error(404, "Not found") }
        if request.method == "POST", parts == ["v1", "pair"] { return pair(request) }

        guard let device = authorize(request) else { return .error(401, "This iPhone isn't paired. Pair it again in the app.") }
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index].lastSeen = Date()
        }
        guard let model else { return .error(503, "Chatterbox is starting.") }

        switch (request.method, parts.count) {
        case ("GET", 2) where parts[1] == "chats":
            return .json(CompanionMapper.chatList(model))
        case ("GET", 3) where parts[1] == "chats":
            guard let session = session(parts[2]) else { return .error(404, "That chat is gone.") }
            let since = request.query["since"].flatMap(Int.init)
            let revision = model.companionRevision(of: session.id)
            if let since, since == revision { return .json(Companion.Unchanged(revision: revision)) }
            return .json(CompanionMapper.detail(session, model: model))
        case ("POST", 4) where parts[1] == "chats" && parts[3] == "messages":
            guard let session = session(parts[2]) else { return .error(404, "That chat is gone.") }
            guard let body = try? Companion.decoder.decode(Companion.SendRequest.self, from: request.body),
                  !body.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .error(400, "Nothing to send.") }
            session.send(body.text)
            return .json(CompanionMapper.detail(session, model: model))
        case ("GET", 5) where parts[1] == "chats" && parts[3] == "files":
            guard let session = session(parts[2]), let fileID = UUID(uuidString: parts[4]),
                  let file = session.allAttachments.first(where: { $0.id == fileID }),
                  let data = try? Data(contentsOf: file.url) else { return .error(404, "That file is gone.") }
            return HTTPResponse(status: 200, contentType: file.mediaType, body: data)
        default:
            return .error(404, "Not found")
        }
    }

    private func session(_ id: String) -> ChatSession? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return model?.sessions.first { $0.id == uuid }
    }

    private func pair(_ request: HTTPRequest) -> HTTPResponse {
        guard isEnabled else { return .error(403, "The iPhone app is turned off in Chatterbox's Settings.") }
        guard let body = try? Companion.decoder.decode(Companion.PairRequest.self, from: request.body) else {
            return .error(400, "Bad request.")
        }
        guard body.code.trimmingCharacters(in: .whitespaces) == pairingCode else {
            failedPairings += 1
            if failedPairings >= 5 { newPairingCode() }
            return .error(403, "That code doesn't match. Check Chatterbox → Settings → iPhone.")
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        let name = body.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        devices.append(Device(name: name.isEmpty ? "iPhone" : String(name.prefix(60)), tokenHash: Self.hash(token)))
        saveDevices()
        newPairingCode()
        return .json(Companion.PairResponse(token: token, macName: Host.current().localizedName ?? "Mac", addresses: Self.addresses))
    }

    private func authorize(_ request: HTTPRequest) -> Device? {
        guard let token = request.headers[Companion.tokenHeader.lowercased()], !token.isEmpty else { return nil }
        let hash = Self.hash(token)
        return devices.first { $0.tokenHash == hash }
    }

    private func saveDevices() {
        if let data = try? JSONEncoder().encode(devices) { UserDefaults.standard.set(data, forKey: Self.devicesKey) }
    }

    // MARK: - Helpers

    private static func newCode() -> String { String(format: "%06d", Int.random(in: 0...999_999)) }

    private static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Only this Mac, the home network, and Tailscale may connect.
    private static func isAllowed(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address):
            let b = [UInt8](address.rawValue)
            return allowed(ipv4Bytes: b)
        case .ipv6(let address):
            let b = [UInt8](address.rawValue)
            guard b.count == 16 else { return false }
            if b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xff, b[11] == 0xff { return allowed(ipv4Bytes: Array(b[12..<16])) }
            if b.dropLast().allSatisfy({ $0 == 0 }), b[15] == 1 { return true }       // ::1
            if b[0] == 0xfe, b[1] & 0xc0 == 0x80 { return true }                       // fe80::/10 link-local
            if b[0] & 0xfe == 0xfc { return true }                                     // fc00::/7, includes Tailscale's fd7a:115c:a1e0::/48
            return false
        default:
            return false
        }
    }

    private static func allowed(ipv4 ip: String) -> Bool {
        allowed(ipv4Bytes: ip.split(separator: ".").compactMap { UInt8($0) })
    }

    private static func allowed(ipv4Bytes b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        return b[0] == 127 || b[0] == 10 || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168)
            || (b[0] == 169 && b[1] == 254) || (b[0] == 100 && (64...127).contains(b[1]))
    }
}

/// Turns chats into what the phone shows.
@MainActor
enum CompanionMapper {
    static func chatList(_ model: AppModel) -> Companion.ChatList {
        var groups: [Companion.ChatGroup] = []
        let projects = model.sidebarProjects
        if !projects.isEmpty {
            groups.append(.init(id: "projects", kind: .projects, title: "Projects", chats: projects.map(summary)))
        }
        for studio in model.activeStudios {
            let chats = model.chats(in: studio)
            groups.append(.init(id: "studio-" + studio.id.uuidString, kind: .studio, title: studio.name, chats: chats.map(summary)))
        }
        let chats = model.sidebarChats.filter { !$0.items.isEmpty }
        if !chats.isEmpty { groups.append(.init(id: "chats", kind: .chats, title: "Chats", chats: chats.map(summary))) }
        return Companion.ChatList(revision: model.companionListRevision, groups: groups)
    }

    static func summary(_ session: ChatSession) -> Companion.ChatSummary {
        let isProject = session.record.projectFolder != nil
        return .init(id: session.id, title: session.title,
                     project: isProject ? session.projectName : nil,
                     subtitle: session.lastActionSummary,
                     backend: session.record.backend.rawValue,
                     isRunning: session.isRunning || session.hasBackgroundWork,
                     isWaitingOnYou: session.isWaitingOnYou,
                     updatedAt: session.record.updatedAt)
    }

    static func detail(_ session: ChatSession, model: AppModel) -> Companion.ChatDetail {
        let all = session.items.filter { !($0.kind == .thought && $0.text.isEmpty) }
        let shown = all.suffix(Companion.itemLimit)
        return .init(revision: model.companionRevision(of: session.id), summary: summary(session),
                     settings: session.settingsDescription,
                     items: shown.map(item), earlierCount: all.count - shown.count)
    }

    static func item(_ item: DisplayItem) -> Companion.Item {
        var text = item.text
        switch item.kind {
        case .questions:
            let asked = (item.questions ?? []).map(\.question).joined(separator: "\n")
            if !asked.isEmpty { text = asked }
        case .approval:
            if let detail = item.detail, !detail.isEmpty { text += "\n" + detail }
        case .plan:
            text = item.planSteps.map { ($0.status == "completed" ? "✓ " : $0.status == "in_progress" ? "→ " : "○ ") + $0.step }.joined(separator: "\n")
        default:
            break
        }
        return .init(id: item.id, kind: Companion.Item.Kind(rawValue: item.kind.rawValue) ?? .notice, text: text,
                     isStreaming: item.phase == .streaming && item.kind == .assistant,
                     isCommentary: item.phase == .commentary,
                     toolState: item.kind == .tool ? item.toolState.rawValue : nil,
                     isPending: item.approvalState == .pending,
                     attachments: (item.attachments ?? []).map { .init(id: $0.id, name: $0.name, mediaType: $0.mediaType, isImage: $0.kind == .image) },
                     isQueued: item.queued == true)
    }
}

/// Just enough HTTP/1.1 for the app's requests.
struct HTTPRequest {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data

    /// Parses a complete request, or returns nil while more bytes are still coming.
    init?(_ data: Data) {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = end.upperBound
        guard data.count - bodyStart >= length else { return nil }
        let target = String(start[1])
        let components = URLComponents(string: target)
        method = String(start[0])
        path = components?.path ?? target
        query = Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        self.headers = headers
        body = data[bodyStart..<(bodyStart + length)]
    }
}

struct HTTPResponse {
    var status: Int
    var contentType: String
    var body: Data

    static func json<T: Encodable>(_ value: T) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "application/json", body: (try? Companion.encoder.encode(value)) ?? Data())
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        var response = json(Companion.ErrorResponse(error: message))
        response.status = status
        return response
    }

    var data: Data {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 503: "Service Unavailable"][status] ?? "Error"
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
