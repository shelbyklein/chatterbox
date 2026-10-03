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
        var push: Companion.PushRegistration? = nil
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
    /// Agents on this Mac (Dot, through chatterbox-mcp) connect here: loopback only, with
    /// a key made fresh at each launch and kept in a file only you can read.
    @ObservationIgnored private var agentListener: NWListener?
    @ObservationIgnored private var agentToken = ""
    @ObservationIgnored private var failedPairings = 0
    @ObservationIgnored private let mutations = CompanionMutationLedger()

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.devicesKey),
           let saved = try? JSONDecoder().decode([Device].self, from: data) {
            devices = saved
        }
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// CHATTERBOX_COMPANION_PORT keeps tests off the port the real app uses.
    static var port: UInt16 {
        ProcessInfo.processInfo.environment["CHATTERBOX_COMPANION_PORT"].flatMap(UInt16.init) ?? Companion.port
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        on ? start() : stop()
    }

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)
            // A test copy on its own port stays off Bonjour, so phones don't see a second Mac.
            if Self.port == Companion.port {
                listener.service = NWListener.Service(name: Host.current().localizedName ?? "Chatterbox", type: Companion.serviceType)
            }
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

    static var agentPort: UInt16 {
        ProcessInfo.processInfo.environment["CHATTERBOX_AGENT_PORT"].flatMap(UInt16.init) ?? 47_320
    }

    static var agentTokenFile: URL {
        if let dir = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir).appendingPathComponent("agent-token")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chatterbox/agent-token")
    }

    /// Starts the local connection for agents. Runs whether or not the iPhone app is on.
    func startAgentListener() {
        guard agentListener == nil else { return }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        agentToken = bytes.map { String(format: "%02x", $0) }.joined()
        let file = Self.agentTokenFile
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: Data(agentToken.utf8), attributes: [.posixPermissions: 0o600])
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.agentPort)!)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection, local: true) }
            }
            listener.start(queue: .main)
            agentListener = listener
        } catch {
            NSLog("Chatterbox: couldn't start the agent connection: \(error)")
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

    private func accept(_ connection: NWConnection, local: Bool = false) {
        guard local ? Self.isLoopback(connection.endpoint) : Self.isAllowed(connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.start(queue: .main)
        receive(on: connection, buffer: Data(), local: local)
    }

    /// Reads one request (headers, then a body up to its Content-Length), answers it, and closes.
    private func receive(on connection: NWConnection, buffer: Data, local: Bool) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return connection.cancel() }
                var buffer = buffer
                if let data { buffer.append(data) }
                if buffer.count > Companion.maxRequestBytes || error != nil { return connection.cancel() }
                switch HTTPRequest.parse(buffer) {
                case .request(let request):
                    let response = self.respond(to: request, local: local)
                    if let file = response.fileURL {
                        HTTPFileTransfer(connection: connection, url: file, contentType: response.contentType).start()
                    } else {
                        connection.send(content: response.data, completion: .contentProcessed { _ in connection.cancel() })
                    }
                case .invalid:
                    let response = HTTPResponse.error(400, "Bad request.")
                    connection.send(content: response.data, completion: .contentProcessed { _ in connection.cancel() })
                case .incomplete where isComplete:
                    connection.cancel()
                case .incomplete:
                    self.receive(on: connection, buffer: buffer, local: local)
                }
            }
        }
    }

    // MARK: - Routes

    func respond(to request: HTTPRequest, local: Bool) -> HTTPResponse {
        var response: HTTPResponse
        let mutation = request.method != "GET" && request.method != "HEAD"
        if !local, mutation, request.path != "/v1/pair", let device = authorize(request) {
            response = mutations.respond(device: device.id, request: request) {
                route(request, local: local)
            }
        } else {
            response = route(request, local: local)
        }
        response.headers.merge(mutations.headers()) { _, new in new }
        return response
    }

    private func route(_ request: HTTPRequest, local: Bool) -> HTTPResponse {
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.first == "v1" else { return .error(404, "Not found") }
        if local {
            // Agents on this Mac: the launch's key, nothing else.
            guard let token = request.headers[Companion.tokenHeader.lowercased()], !agentToken.isEmpty, token == agentToken else {
                return .error(401, "Chatterbox's agent key doesn't match. Is Chatterbox running?")
            }
        } else {
            if request.method == "POST", parts == ["v1", "pair"] { return pair(request) }
            guard let device = authorize(request) else { return .error(401, "This iPhone isn't paired. Pair it again in the app.") }
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                devices[index].lastSeen = Date()
            }
        }
        if !local, parts == ["v1", "push"], let device = authorize(request) {
            if request.method == "DELETE" {
                clearPush(device.id)
                return .json(["ok": true])
            }
            if request.method == "POST" {
                guard var registration = try? Companion.decoder.decode(Companion.PushRegistration.self, from: request.body), registration.valid else {
                    return .error(400, "Invalid push registration.")
                }
                registration.token = registration.token.lowercased()
                guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return .error(401, "Device revoked.") }
                devices[index].push = registration
                saveDevices()
                return .json(["ok": true])
            }
        }
        guard let model else { return .error(503, "Chatterbox is starting.") }

        // Dot's computer, for Dot's own tools on this Mac.
        if local, parts.count >= 2, parts[1] == "computer" {
            return computerRoute(request.method, parts.count > 2 ? parts[2] : nil, body: request.body, model: model)
        }

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
            guard let body = try? Companion.decoder.decode(Companion.SendRequest.self, from: request.body) else {
                return .error(400, "Bad request.")
            }
            var images: [Attachment] = []
            for upload in body.images ?? [] {
                do { images.append(try Attachments.importImageData(upload.data, name: upload.name)) } catch {
                    return .error(400, "Couldn't read \(upload.name): \(error.localizedDescription)")
                }
            }
            guard !body.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else {
                return .error(400, "Nothing to send.")
            }
            if body.now == true { session.sendNow(body.text, attachments: images) } else { session.send(body.text, attachments: images) }
            if local, body.fromDot == true, !session.isDot { session.record.dotFollowing = true }
            return .json(CompanionMapper.detail(session, model: model))
        case ("POST", 2) where parts[1] == "chats":
            let body = (try? Companion.decoder.decode(Companion.NewChatRequest.self, from: request.body)) ?? .init()
            let backend = body.backend.flatMap(Backend.init(rawValue:))
            // Starting a chat from the phone leaves the Mac showing what it was.
            let shown = model.selectedID
            let session: ChatSession
            if let id = body.studio {
                guard let studio = model.studio(id), studio.archivedAt == nil else { return .error(404, "That Studio is gone.") }
                session = model.newChat(in: studio, backend: backend)
            } else {
                session = model.newChat(backend: backend)
            }
            if let shown, model.sessions.contains(where: { $0.id == shown }) { model.selectedID = shown }
            return .json(CompanionMapper.detail(session, model: model))
        case ("POST", 4) where parts[1] == "chats" && parts[3] == "settings":
            guard let session = session(parts[2]) else { return .error(404, "That chat is gone.") }
            guard let body = try? Companion.decoder.decode(Companion.SettingsRequest.self, from: request.body) else { return .error(400, "Bad settings.") }
            CompanionMapper.apply(body, to: session)
            return .json(CompanionMapper.detail(session, model: model))
        case ("POST", 4) where parts[1] == "chats" && parts[3] == "rename":
            guard let session = session(parts[2]) else { return .error(404, "That chat is gone.") }
            guard let body = try? Companion.decoder.decode(Companion.RenameRequest.self, from: request.body) else { return .error(400, "Bad name.") }
            if session.isDot { model.renameDot(body.title) } else { session.setTitle(body.title) }
            return .json(CompanionMapper.detail(session, model: model))
        case ("POST", 4) where parts[1] == "chats" && (parts[3] == "archive" || parts[3] == "unarchive"):
            guard let session = session(parts[2]) else { return .error(404, "That chat is gone.") }
            let shown = model.selectedID
            if parts[3] == "archive" { model.archive(session) } else { session.setArchived(false) }
            if let shown, shown != session.id, model.sessions.contains(where: { $0.id == shown }) { model.selectedID = shown }
            return .json(CompanionMapper.detail(session, model: model))
        case ("POST", 4) where parts[1] == "chats" && parts[3] == "fork":
            guard let session = session(parts[2]) else { return .error(404, "That chat is gone.") }
            let shown = model.selectedID
            guard let fork = model.fork(session) else { return .error(409, "This chat can't be forked right now.") }
            if let shown { model.selectedID = shown }
            return .json(CompanionMapper.detail(fork, model: model))
        case ("POST", 4) where parts[1] == "pins" && parts[3] == "open":
            guard let id = UUID(uuidString: parts[2]), let pin = PinStore.shared.pins.first(where: { $0.id == id }) else {
                return .error(404, "That pin is gone.")
            }
            // Opens on the Mac's screen, as clicking it there would.
            PinStore.shared.open(pin)
            return .json(Companion.Unchanged(unchanged: false, revision: 0))
        case ("POST", 4) where parts[1] == "studios" && parts[3] == "instructions":
            guard let id = UUID(uuidString: parts[2]), model.studio(id) != nil else { return .error(404, "That Studio is gone.") }
            guard let body = try? Companion.decoder.decode(Companion.InstructionsRequest.self, from: request.body) else { return .error(400, "Bad request.") }
            model.setInstructions(body.text, forStudio: id)
            return .json(CompanionMapper.chatList(model))
        case ("POST", 4) where parts[1] == "chats" && parts[3] == "stop":
            guard let session = session(parts[2]) else { return .error(404, "That chat is gone.") }
            if session.canStop { session.interrupt() }
            return .json(CompanionMapper.detail(session, model: model))
        // Approvals and answers are the user's alone: agents on this Mac (Golem) may only suggest.
        case ("POST", 5) where local && parts[1] == "chats" && (parts[3] == "approvals" || parts[3] == "answers"):
            return .error(403, "Only the user can answer approvals and questions. Use suggest_answer to propose an answer for them to send.")
        case ("POST", 5) where local && parts[1] == "chats" && parts[3] == "suggestions":
            guard let session = session(parts[2]), let itemID = UUID(uuidString: parts[4]) else { return .error(404, "That chat is gone.") }
            guard let body = try? Companion.decoder.decode(Companion.SuggestionRequest.self, from: request.body) else { return .error(400, "Bad suggestion.") }
            do {
                try session.suggestAnswers(itemID, answers: body.answers, reason: body.reason, by: model.dotName)
            } catch let error as ChatSession.SuggestionError {
                return .error(409, error.message)
            } catch { return .error(400, "Bad suggestion.") }
            return .json(CompanionMapper.detail(session, model: model))
        case ("POST", 2) where local && parts[1] == "decisions":
            guard let body = try? Companion.decoder.decode(Companion.DecisionNote.self, from: request.body),
                  !body.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .error(400, "Nothing to record.") }
            let chat = body.chat.flatMap { session($0) }
            GolemJournal.shared.add(.decision, title: body.summary, detail: body.why, chat: chat)
            return .json(["ok": true])
        case ("POST", 5) where parts[1] == "chats" && parts[3] == "approvals":
            guard let session = session(parts[2]), let itemID = UUID(uuidString: parts[4]) else { return .error(404, "That chat is gone.") }
            guard let body = try? Companion.decoder.decode(Companion.DecisionRequest.self, from: request.body),
                  let decision = DisplayItem.ApprovalState(rawValue: body.decision),
                  [.approved, .approvedForSession, .denied].contains(decision) else { return .error(400, "Bad decision.") }
            guard session.items.contains(where: { $0.id == itemID && $0.approvalState == .pending }) else {
                return .error(409, "That was already answered.")
            }
            session.resolveApproval(itemID, decision)
            return .json(CompanionMapper.detail(session, model: model))
        case ("POST", 5) where parts[1] == "chats" && parts[3] == "answers":
            guard let session = session(parts[2]), let itemID = UUID(uuidString: parts[4]) else { return .error(404, "That chat is gone.") }
            guard let body = try? Companion.decoder.decode(Companion.AnswersRequest.self, from: request.body) else { return .error(400, "Bad answers.") }
            guard session.items.contains(where: { $0.id == itemID && $0.approvalState == .pending }) else {
                return .error(409, "Those questions were already answered.")
            }
            session.answerQuestions(itemID, answers: body.answers)
            return .json(CompanionMapper.detail(session, model: model))
        case ("POST", 6) where parts[1] == "chats" && parts[3] == "queued" && parts[5] == "now":
            guard let session = session(parts[2]), let itemID = UUID(uuidString: parts[4]) else { return .error(404, "That chat is gone.") }
            session.sendQueuedNow(itemID)
            return .json(CompanionMapper.detail(session, model: model))
        case ("GET", 2) where parts[1] == "addresses":
            return .json(Companion.Addresses(addresses: Self.addresses))
        case ("GET", 2) where parts[1] == "avatar":
            return .json(CompanionMapper.avatarList())
        case ("GET", 3) where parts[1] == "avatar":
            // Only a file listed in the Avatar folder, by its plain name.
            guard let file = CompanionMapper.avatarList().files.first(where: { $0.name == parts[2] }),
                  let data = try? Data(contentsOf: GolemAvatar.folder.appendingPathComponent(file.name)) else {
                return .error(404, "No such animation.")
            }
            let type = file.name.hasSuffix(".png") ? "image/png" : file.name.hasSuffix(".json") ? "application/json" : "video/quicktime"
            return HTTPResponse(status: 200, contentType: type, body: data)
        case ("GET", 5) where parts[1] == "chats" && parts[3] == "files":
            guard let session = session(parts[2]), let fileID = UUID(uuidString: parts[4]) else { return .error(404, "That file is gone.") }
            if let file = session.allAttachments.first(where: { $0.id == fileID }) {
                return HTTPResponse(status: 200, contentType: file.mediaType, body: Data(), fileURL: file.url)
            }
            // An animation a reply points to.
            for item in session.items where item.kind == .assistant {
                for url in ChatSession.referencedMedia(in: item.text, folder: session.workingFolder) + ChatSession.referencedImages(in: item.text, folder: session.workingFolder) + CompanionDocuments.referenced(in: item.text, folder: session.workingFolder)
                where ChatSession.mediaID(url.path) == fileID {
                    return HTTPResponse(status: 200, contentType: url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "application/octet-stream", body: Data(), fileURL: url)
                }
            }
            return .error(404, "That file is gone.")
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

    func clearPush(_ device: UUID, token: String? = nil) {
        guard let index = devices.firstIndex(where: { $0.id == device }),
              token == nil || devices[index].push?.token == token else { return }
        devices[index].push = nil
        saveDevices()
    }

    private func saveDevices() {
        if let data = try? JSONEncoder().encode(devices) { UserDefaults.standard.set(data, forKey: Self.devicesKey) }
    }

    // MARK: - Helpers

    private static func newCode() -> String { String(format: "%06d", Int.random(in: 0...999_999)) }

    private static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address.rawValue.first == 127
        case .ipv6(let address): return address == .loopback
        default: return false
        }
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
    private static var lastCodexModelsTry = Date.distantPast

    static func chatList(_ model: AppModel) -> Companion.ChatList {
        var groups: [Companion.ChatGroup] = []
        // Dot first, as at the top of the sidebar.
        groups.append(.init(id: "dot", kind: .dot, title: model.dotName, chats: [summary(model.ensureDot())]))
        let projects = model.sidebarProjects
        if !projects.isEmpty {
            // Each project followed by its worktrees, as nested under it in the sidebar.
            let chats = projects.flatMap { [$0] + model.worktrees(of: $0) }
            groups.append(.init(id: "projects", kind: .projects, title: "Projects", chats: chats.map(summary)))
        }
        for studio in model.activeStudios {
            let chats = model.chats(in: studio)
            let place = PinPlace(key: "studio:" + studio.id.uuidString, name: studio.name)
            groups.append(.init(id: "studio-" + studio.id.uuidString, kind: .studio, title: studio.name, chats: chats.map(summary),
                                studioID: studio.id, instructions: studio.instructions,
                                pins: PinStore.shared.pins(in: place).map(pin)))
        }
        let chats = model.sidebarChats.filter { !$0.items.isEmpty }
        if !chats.isEmpty { groups.append(.init(id: "chats", kind: .chats, title: "Chats", chats: chats.map(summary))) }
        return Companion.ChatList(revision: model.companionListRevision, groups: groups, pins: PinStore.shared.globalPins.map(pin))
    }

    static func pin(_ pin: Pin) -> Companion.Pin {
        .init(id: pin.id, title: pin.title, kind: pin.kind.rawValue,
              target: pin.kind == .website ? (PinStore.normalizedURL(pin.target)?.absoluteString ?? pin.target) : pin.target)
    }

    /// The animations (.mov), the live rig (golem.json and its .png stones) and head image in
    /// the assistant's Avatar folder.
    static func avatarList() -> Companion.AvatarList {
        let entries = (try? FileManager.default.contentsOfDirectory(at: GolemAvatar.folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return .init(files: entries.filter { ["mov", "png", "json"].contains($0.pathExtension.lowercased()) }.map { url in
            .init(name: url.lastPathComponent,
                  modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }.sorted { $0.name < $1.name })
    }

    static func summary(_ session: ChatSession) -> Companion.ChatSummary {
        let isProject = session.record.projectFolder != nil
        return .init(id: session.id, title: session.title,
                     project: isProject ? session.projectName : nil,
                     subtitle: session.lastActionSummary,
                     backend: session.record.backend.rawValue,
                     isRunning: session.isRunning || session.hasBackgroundWork,
                     isWaitingOnYou: session.isWaitingOnYou,
                     updatedAt: session.record.updatedAt,
                     pins: isProject ? PinStore.shared.pins(in: PinPlace(key: "project:" + (session.record.projectFolder ?? ""), name: session.projectName)).map(pin) : nil,
                     isDot: session.isDot ? true : nil,
                     unread: session.isDot ? Attention.shared.dotUnreadCount(session) : nil,
                     worktreeBranch: session.record.worktreeOf != nil ? (session.record.worktreeBranch ?? session.projectName) : nil)
    }

    static func detail(_ session: ChatSession, model: AppModel) -> Companion.ChatDetail {
        let all = session.items.filter { !($0.kind == .thought && $0.text.isEmpty) }
        let shown = all.suffix(Companion.itemLimit)
        let folder = session.workingFolder
        return .init(revision: model.companionRevision(of: session.id), summary: summary(session),
                     settings: session.settingsDescription,
                     items: shown.map { item($0, folder: folder) }, earlierCount: all.count - shown.count,
                     options: options(session), isArchived: session.record.archivedAt != nil,
                     canFork: model.canFork(session),
                     turnStartedAt: session.isRunning ? session.record.turnStartedAt : nil,
                     backgroundTasks: session.backgroundTasks.map {
                         .init(id: $0.id, kind: $0.kind.rawValue, title: $0.title, detail: $0.detail, startedAt: $0.startedAt)
                     },
                     contextFraction: session.contextUsage[session.record.backend]?.fraction,
                     contextTokens: session.contextUsage[session.record.backend]?.used,
                     folder: session.workingFolder,
                     commands: commands(session).map { .init(name: $0.name, detail: $0.description, argumentHint: $0.argumentHint) },
                     nextSteps: NextSteps.shared.suggestions(for: session).nilIfEmpty)
    }

    /// The chat's slash commands, or its Codex skills, as the Mac's "/" menu lists them.
    static func commands(_ session: ChatSession) -> [SlashCommand] {
        if session.record.backend == .codex {
            return session.record.codex.map { CodexAppServer.shared.skills[$0.folder] ?? [] } ?? []
        }
        return session.claudeCommands ?? ClaudeModels.shared.commands
    }

    static func options(_ session: ChatSession) -> Companion.ChatOptions {
        let isCodex = session.record.backend == .codex
        // The phone asking is reason enough to learn Codex's models, if nothing has yet.
        if CodexAppServer.shared.models.isEmpty, Date().timeIntervalSince(lastCodexModelsTry) > 60 {
            lastCodexModelsTry = Date()
            Task { try? await CodexAppServer.shared.ensureStarted(); try? await CodexAppServer.shared.refreshModels() }
        }
        let claude = ClaudeModels.shared.models.map {
            Companion.ModelOption(id: $0.value, name: $0.displayName, detail: $0.detail, efforts: $0.efforts, defaultEffort: nil)
        }
        let codex = [Companion.ModelOption(id: "", name: "Codex default", detail: "Whatever Codex uses when none is picked", efforts: [], defaultEffort: nil)]
            + CodexAppServer.shared.models.filter { !$0.hidden }.map {
                Companion.ModelOption(id: $0.model, name: $0.displayName, detail: $0.isDefault ? "Codex's default" : "",
                                      efforts: $0.efforts, defaultEffort: $0.defaultEffort)
            }
        let modes = PermissionModes.modes(for: session.record.backend).map {
            Companion.ModeOption(id: $0.id, title: $0.title, detail: $0.detail, systemImage: $0.systemImage, isUnrestricted: $0.isUnrestricted)
        }
        let presets = ModelPresets.shared.presets.map {
            Companion.PresetOption(id: $0.id, title: $0.title, backend: $0.backend.rawValue, isActive: ModelPresets.shared.matches($0, session: session))
        }
        return .init(backend: session.record.backend.rawValue,
                     model: isCodex ? (session.record.codex?.model ?? "") : session.record.model,
                     effort: isCodex ? (session.record.codex?.effort ?? "") : session.record.effort,
                     claudeModels: claude, codexModels: codex, modes: modes, mode: session.mode.id, presets: presets,
                     fastMode: session.supportsFastMode ? session.fastMode : nil)
    }

    /// Changes a chat's settings the way the Mac's controls do.
    static func apply(_ change: Companion.SettingsRequest, to session: ChatSession) {
        if let backend = change.backend.flatMap(Backend.init(rawValue:)), backend != session.record.backend {
            session.setBackend(backend)
        }
        let isCodex = session.record.backend == .codex
        if let model = change.model {
            if isCodex { session.setCodexModel(model.isEmpty ? nil : model) } else if !model.isEmpty { session.setModel(model) }
        }
        if let effort = change.effort {
            if isCodex { session.setCodexEffort(effort.isEmpty ? nil : effort) } else { session.setEffort(effort) }
        }
        if let mode = change.mode { session.setMode(mode) }
        if let fast = change.fastMode { session.setFastMode(fast) }
        if let id = change.preset, let preset = ModelPresets.shared.presets.first(where: { $0.id == id }) {
            ModelPresets.shared.apply(preset, to: session)
        }
    }

    static func item(_ item: DisplayItem, folder: String? = nil) -> Companion.Item {
        var mapped = plainItem(item)
        // Animations a final reply points to travel with it, to play on the phone.
        if item.kind == .assistant, item.phase == .final {
            mapped.attachments += ChatSession.referencedMedia(in: item.text, folder: folder).map {
                .init(id: ChatSession.mediaID($0.path), name: $0.lastPathComponent, mediaType: "application/octet-stream", isImage: false)
            }
            // Screenshots and renders it names, as pictures to view.
            mapped.attachments += ChatSession.referencedImages(in: item.text, folder: folder).map {
                .init(id: ChatSession.mediaID($0.path), name: $0.lastPathComponent, mediaType: "image/" + $0.pathExtension.lowercased(), isImage: true)
            }
        }
        var documents: [(URL, UUID)] = []
        for attachment in item.attachments ?? [] where attachment.url.pathExtension.lowercased() == "pdf" {
            documents.append((attachment.url, attachment.id))
            if let index = mapped.attachments.firstIndex(where: { $0.id == attachment.id }) {
                mapped.attachments[index] = CompanionDocuments.metadata(id: attachment.id, url: attachment.url, name: attachment.name)
            }
        }
        if item.kind == .assistant {
            for url in CompanionDocuments.referenced(in: item.text, folder: folder) {
                let id = documents.first(where: { $0.0.resolvingSymlinksInPath() == url })?.1 ?? ChatSession.mediaID(url.path)
                if !mapped.attachments.contains(where: { $0.id == id }) {
                    mapped.attachments.append(CompanionDocuments.metadata(id: id, url: url))
                }
                documents.append((url, id))
            }
        }
        mapped.text = CompanionDocuments.rewrite(mapped.text, folder: folder, documents: documents)
        return mapped
    }

    private static func plainItem(_ item: DisplayItem) -> Companion.Item {
        // Dot's check-ins read as a small line on the phone too.
        if item.kind == .user, item.automatic == true {
            return .init(id: item.id, kind: .notice, text: item.detail ?? "Check-in", isStreaming: false, isCommentary: false,
                         toolState: nil, isPending: false, attachments: [], isQueued: false)
        }
        var text = item.text
        switch item.kind {
        case .questions:
            let asked = (item.questions ?? []).map(\.question).joined(separator: "\n")
            if !asked.isEmpty { text = asked }
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
                     isQueued: item.queued == true,
                     approval: item.kind == .approval
                        ? .init(isPlan: item.approvalStyle == .plan, state: (item.approvalState ?? .expired).rawValue) : nil,
                     questions: item.questions?.map { q in
                         .init(id: q.id, header: q.header, question: q.question,
                               options: q.options.map { .init(label: $0.label, detail: $0.detail) },
                               multiSelect: q.multiSelect, isSecret: q.isSecret)
                     },
                     answers: item.answers,
                     suggested: item.approvalState == .pending ? item.suggested : nil,
                     suggestedReason: item.approvalState == .pending ? item.suggestedReason : nil,
                     detail: item.kind == .approval || item.kind == .shell ? item.detail.map { String($0.suffix(20_000)) } : nil,
                     planSteps: item.kind == .plan ? item.planSteps.map { .init(step: $0.step, status: $0.status) } : nil,
                     workedSeconds: item.workedSeconds)
    }
}

/// Just enough HTTP/1.1 for the app's requests.
struct HTTPRequest {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data

    enum Parse {
        /// More bytes are still coming.
        case incomplete
        /// Can never become a valid request (a bad request line or Content-Length).
        case invalid
        case request(HTTPRequest)
    }

    /// Parses a request once all of it has arrived. This runs before pairing or the token is
    /// checked, so anything malformed is rejected, never trusted.
    static func parse(_ data: Data) -> Parse {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        // Only plain digits, within the request size limit ("-1", "+5", "1e3", "abc" are refused).
        let lengthText = headers["content-length"] ?? "0"
        guard !lengthText.isEmpty, lengthText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let length = Int(lengthText), length <= Companion.maxRequestBytes else { return .invalid }
        let bodyStart = end.upperBound
        guard data.count - bodyStart >= length else { return .incomplete }
        let target = String(start[1])
        let components = URLComponents(string: target)
        return .request(HTTPRequest(
            method: String(start[0]), path: components?.path ?? target,
            query: Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 }),
            headers: headers, body: Data(data[bodyStart..<(bodyStart + length)])))
    }
}

extension CompanionServer {
    /// What Dot's computer is doing, and starting, stopping, or showing it. Starting takes a
    /// while (Docker may have to open), so it answers at once and the caller checks back.
    fileprivate func computerRoute(_ method: String, _ action: String?, body: Data, model: AppModel) -> HTTPResponse {
        let computer = DotComputer.shared
        switch (method, action) {
        case ("GET", "downloads"):
            return .json(ComputerHandoff.downloads())
        case ("POST", "handoff"):
            guard let request = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let file = request["file"] as? String,
                  let chat = (request["chat"] as? String).flatMap(UUID.init(uuidString:)),
                  let session = model.sessions.first(where: { $0.id == chat }) else {
                return .error(400, "Say which downloaded file to hand off.")
            }
            do {
                return .json(try ComputerHandoff.handOff(file, to: request["to"] as? String, for: session))
            } catch {
                return .error(400, error.localizedDescription)
            }
        case ("GET", "previews"):
            let previews = PreviewRelays.shared
            return .json(previews.enabled.sorted().map { port in
                ["url": "http://localhost:\(port)", "title": previews.sites.first { $0.port == port }?.title ?? "localhost:\(port)"]
            })
        case ("GET", nil):
            break
        case ("POST", "start"):
            switch computer.state {
            case .running, .starting, .building: break
            case .noDocker: return .error(409, "Docker isn't installed on this Mac, so the computer can't run. The user can install Docker Desktop.")
            case .notSetUp: Task { await model.setUpDotComputer() }
            default: Task { await model.startDotComputer() }
            }
        case ("POST", "stop"):
            if computer.isRunning { Task { await model.stopDotComputer() } }
        case ("POST", "show"):
            NotificationCenter.default.post(name: .showDotComputer, object: nil)
        default:
            return .error(404, "Not found")
        }
        return .json(Companion.ComputerStatus(state: computer.stateName, detail: computer.stateDetail))
    }
}

extension Notification.Name {
    /// Opens the window with Dot's computer screen.
    static let showDotComputer = Notification.Name("ChatterboxShowDotComputer")
}

struct HTTPResponse {
    var status: Int
    var contentType: String
    var body: Data
    var fileURL: URL? = nil
    var headers: [String: String] = [:]

    static func json<T: Encodable>(_ value: T) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "application/json", body: (try? Companion.encoder.encode(value)) ?? Data())
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        var response = json(Companion.ErrorResponse(error: message))
        response.status = status
        return response
    }

    var data: Data {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
                      409: "Conflict", 503: "Service Unavailable"][status] ?? "Error"
        let extra = headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)\r\n" }.joined()
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\(extra)\r\n"
        return Data(head.utf8) + body
    }
}

/// Files the agent computer downloaded, and handing one to a chat's project on the Mac.
/// Only the computer's Downloads folder is read, and a file only ever lands inside the
/// chat's own folder (its project, Studio, or working folder).
enum ComputerHandoff {
    struct Download: Encodable {
        var name: String
        var bytes: Int
        var modified: Date
    }

    struct Result: Encodable {
        var path: String
        var bytes: Int
    }

    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static func downloads() -> [Download] {
        let folder = DotComputer.downloadsFolder
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true, !url.lastPathComponent.hasSuffix(".crdownload") else { return nil }
            // The browser tool's own page snapshots: not downloads. Old ones are cleared away.
            if url.lastPathComponent.range(of: #"^page-\d{4}-.*\.yml$"#, options: .regularExpression) != nil {
                if Date().timeIntervalSince(values?.contentModificationDate ?? Date()) > 600 { try? FileManager.default.removeItem(at: url) }
                return nil
            }
            return Download(name: url.lastPathComponent, bytes: values?.fileSize ?? 0, modified: values?.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.modified > $1.modified }
    }

    /// Copies `name` from the computer's Downloads into the chat's folder: `to` (a path
    /// relative to that folder, a folder if it ends in /), or handoff/<name> by default.
    @MainActor
    static func handOff(_ name: String, to destination: String?, for session: ChatSession) throws -> Result {
        let fm = FileManager.default
        let inbox = DotComputer.downloadsFolder.standardizedFileURL.resolvingSymlinksInPath()
        let source = inbox.appendingPathComponent(name).standardizedFileURL.resolvingSymlinksInPath()
        guard !name.contains("/"), source.deletingLastPathComponent().path == inbox.path,
              fm.fileExists(atPath: source.path) else {
            throw Failure(message: "No downloaded file named \u{201C}\(name)\u{201D}. Use list_computer_downloads to see what's there.")
        }
        let root = URL(fileURLWithPath: session.workingFolder).standardizedFileURL.resolvingSymlinksInPath()
        let relative = (destination?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "handoff/"
        guard !relative.hasPrefix("/"), !relative.hasPrefix("~") else {
            throw Failure(message: "Give a path inside this chat's folder, like handoff/ or assets/photos/.")
        }
        var target = root.appendingPathComponent(relative)
        if relative.hasSuffix("/") { target = target.appendingPathComponent(name) }
        target = target.standardizedFileURL
        guard target.path.hasPrefix(root.path + "/") else {
            throw Failure(message: "That's outside this chat's folder (\(root.path)).")
        }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The resolved parent must still be inside (no symlink out of the project).
        guard target.deletingLastPathComponent().resolvingSymlinksInPath().path.hasPrefix(root.path) else {
            throw Failure(message: "That's outside this chat's folder.")
        }
        // Never overwrite: a second copy gets a number.
        var final = target
        var n = 2
        while fm.fileExists(atPath: final.path) {
            let base = target.deletingPathExtension().lastPathComponent, ext = target.pathExtension
            final = target.deletingLastPathComponent().appendingPathComponent("\(base)-\(n)" + (ext.isEmpty ? "" : ".\(ext)"))
            n += 1
        }
        try fm.copyItem(at: source, to: final)
        let bytes = (try? final.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Result(path: final.path, bytes: bytes)
    }
}
