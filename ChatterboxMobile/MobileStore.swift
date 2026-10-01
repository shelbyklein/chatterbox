import Foundation
import Network
import Observation
import Security
import UIKit

struct MobileError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// The connection to Chatterbox on the Mac: where it is, the token from pairing, and the
/// calls the app makes. It tries the address that last worked first, then the others (the
/// home network, Tailscale), so it keeps working when the phone leaves the house.
@MainActor
@Observable
final class MobileStore {
    struct Connection: Codable {
        var macName: String
        /// Addresses to try, most recently working first.
        var hosts: [String]
    }

    private(set) var connection: Connection?
    private(set) var chatList: Companion.ChatList?
    /// Why the last call failed, shown until one works again.
    private(set) var problem: String?
    @ObservationIgnored private var token: String?

    var isPaired: Bool { connection != nil && token != nil }

    init() {
        if let data = UserDefaults.standard.data(forKey: "connection") {
            connection = try? JSONDecoder().decode(Connection.self, from: data)
        }
        token = Keychain.read("token")
    }

    // MARK: - Pairing

    func pair(host: String, code: String) async throws {
        let body = try JSONEncoder().encode(Companion.PairRequest(code: code, deviceName: UIDevice.current.name))
        let (data, response) = try await URLSession.shared.data(for: request(host: host, path: "/v1/pair", method: "POST", body: body, token: nil))
        try checkStatus(data, response)
        let reply = try Companion.decoder.decode(Companion.PairResponse.self, from: data)
        var hosts = [host]
        for address in reply.addresses where !hosts.contains(address) { hosts.append(address) }
        token = reply.token
        Keychain.save("token", reply.token)
        connection = Connection(macName: reply.macName, hosts: hosts)
        saveConnection()
        problem = nil
    }

    func forget() {
        Keychain.delete("token")
        token = nil
        connection = nil
        chatList = nil
        UserDefaults.standard.removeObject(forKey: "connection")
    }

    // MARK: - Calls

    func loadChats() async {
        do {
            chatList = try await call("/v1/chats")
        } catch {
            note(error)
        }
    }

    enum DetailResult {
        case unchanged
        case detail(Companion.ChatDetail)
    }

    func detail(_ id: UUID, since revision: Int?) async throws -> DetailResult {
        let path = "/v1/chats/\(id.uuidString)" + (revision.map { "?since=\($0)" } ?? "")
        let data = try await raw(path)
        if let unchanged = try? Companion.decoder.decode(Companion.Unchanged.self, from: data), unchanged.unchanged {
            return .unchanged
        }
        return .detail(try Companion.decoder.decode(Companion.ChatDetail.self, from: data))
    }

    /// `now` stops the agent and sends right away ("Send Now").
    func send(_ text: String, images: [Companion.Upload] = [], now: Bool = false, to id: UUID) async throws -> Companion.ChatDetail {
        let body = try JSONEncoder().encode(Companion.SendRequest(text: text, images: images.isEmpty ? nil : images, now: now ? true : nil))
        return try await call("/v1/chats/\(id.uuidString)/messages", method: "POST", body: body)
    }

    func stop(_ id: UUID) async throws -> Companion.ChatDetail {
        try await call("/v1/chats/\(id.uuidString)/stop", method: "POST", body: Data("{}".utf8))
    }

    /// "approved", "approvedForSession", or "denied".
    func decide(_ decision: String, item: UUID, in chat: UUID) async throws -> Companion.ChatDetail {
        let body = try JSONEncoder().encode(Companion.DecisionRequest(decision: decision))
        return try await call("/v1/chats/\(chat.uuidString)/approvals/\(item.uuidString)", method: "POST", body: body)
    }

    /// nil skips the questions.
    func answer(_ answers: [String: [String]]?, item: UUID, in chat: UUID) async throws -> Companion.ChatDetail {
        let body = try JSONEncoder().encode(Companion.AnswersRequest(answers: answers))
        return try await call("/v1/chats/\(chat.uuidString)/answers/\(item.uuidString)", method: "POST", body: body)
    }

    // MARK: Chat settings and management

    func newChat(in studio: UUID?, backend: String?) async throws -> Companion.ChatDetail {
        let body = try JSONEncoder().encode(Companion.NewChatRequest(studio: studio, backend: backend))
        return try await call("/v1/chats", method: "POST", body: body)
    }

    func change(_ settings: Companion.SettingsRequest, in chat: UUID) async throws -> Companion.ChatDetail {
        try await call("/v1/chats/\(chat.uuidString)/settings", method: "POST", body: try JSONEncoder().encode(settings))
    }

    func rename(_ chat: UUID, to title: String) async throws -> Companion.ChatDetail {
        try await call("/v1/chats/\(chat.uuidString)/rename", method: "POST", body: try JSONEncoder().encode(Companion.RenameRequest(title: title)))
    }

    func setArchived(_ archived: Bool, chat: UUID) async throws -> Companion.ChatDetail {
        try await call("/v1/chats/\(chat.uuidString)/\(archived ? "archive" : "unarchive")", method: "POST", body: Data("{}".utf8))
    }

    func fork(_ chat: UUID) async throws -> Companion.ChatDetail {
        try await call("/v1/chats/\(chat.uuidString)/fork", method: "POST", body: Data("{}".utf8))
    }

    /// Opens an app, file, or Shortcut pin on the Mac.
    func openOnMac(_ pin: Companion.Pin) async throws {
        _ = try await raw("/v1/pins/\(pin.id.uuidString)/open", method: "POST", body: Data("{}".utf8))
    }

    func setInstructions(_ text: String, studio: UUID) async throws {
        chatList = try await call("/v1/studios/\(studio.uuidString)/instructions", method: "POST",
                                  body: try JSONEncoder().encode(Companion.InstructionsRequest(text: text)))
    }

    func sendQueuedNow(_ item: UUID, in chat: UUID) async throws -> Companion.ChatDetail {
        try await call("/v1/chats/\(chat.uuidString)/queued/\(item.uuidString)/now", method: "POST", body: Data("{}".utf8))
    }

    func file(_ file: Companion.File, in chat: UUID) async throws -> Data {
        try await raw("/v1/chats/\(chat.uuidString)/files/\(file.id.uuidString)")
    }

    // MARK: - Plumbing

    private func call<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        try Companion.decoder.decode(T.self, from: try await raw(path, method: method, body: body))
    }

    /// Tries each known address until one answers, and remembers the one that did.
    private func raw(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let connection, let token else { throw MobileError(message: "This iPhone isn't paired.") }
        var lastError: Error = MobileError(message: "Couldn't reach \(connection.macName).")
        for host in connection.hosts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request(host: host, path: path, method: method, body: body, token: token))
                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    forget()
                    throw MobileError(message: "This iPhone was removed from Chatterbox on the Mac. Pair it again.")
                }
                try checkStatus(data, response)
                if host != connection.hosts.first { moveToFront(host) }
                if problem != nil { problem = nil }
                return data
            } catch let error as MobileError {
                throw error
            } catch {
                lastError = error
            }
        }
        throw MobileError(message: "Can't reach \(connection.macName). Make sure Chatterbox is open on it, and that you're on the same Wi-Fi or Tailscale is on. (\(lastError.localizedDescription))")
    }

    private func request(host: String, path: String, method: String, body: Data?, token: String?) -> URLRequest {
        let address = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        var request = URLRequest(url: URL(string: "http://\(address):\(Self.port)\(path)")!)
        request.httpMethod = method
        request.httpBody = body
        // Images take longer to send than a message.
        request.timeoutInterval = (body?.count ?? 0) > 200_000 ? 60 : 6
        if let token { request.setValue(token, forHTTPHeaderField: Companion.tokenHeader) }
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    /// Throws the Mac's error message when a call didn't succeed.
    private func checkStatus(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode != 200 else { return }
        let message = (try? Companion.decoder.decode(Companion.ErrorResponse.self, from: data))?.error
        throw MobileError(message: message ?? "Chatterbox answered with error \(http.statusCode).")
    }

    /// Simulator tests reach a test copy of the Mac app on its own port, never the real one.
    private static var port: UInt16 {
        #if DEBUG
        if let test = ProcessInfo.processInfo.environment["CHATTERBOX_TEST_PORT"].flatMap(UInt16.init) { return test }
        #endif
        return Companion.port
    }

    private func moveToFront(_ host: String) {
        guard var connection else { return }
        connection.hosts.removeAll { $0 == host }
        connection.hosts.insert(host, at: 0)
        self.connection = connection
        saveConnection()
    }

    private func saveConnection() {
        if let data = try? JSONEncoder().encode(connection) { UserDefaults.standard.set(data, forKey: "connection") }
    }

    private func note(_ error: Error) {
        problem = error.localizedDescription
    }
}

/// Finds Chatterbox on the same Wi-Fi with Bonjour, and turns what it finds into an address.
@MainActor
@Observable
final class MacFinder {
    struct Found: Identifiable, Hashable {
        var id: String { name }
        var name: String
        var endpoint: NWEndpoint
    }

    private(set) var found: [Found] = []
    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: Companion.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> Found? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return Found(name: name, endpoint: result.endpoint)
            }
            Task { @MainActor in self?.found = found.sorted { $0.name < $1.name } }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Connects briefly to learn the Mac's IPv4 address.
    func address(of mac: Found) async -> String? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: mac.endpoint, using: parameters)
        return await withCheckedContinuation { continuation in
            let once = Once(continuation, connection: connection)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint {
                        var text = "\(host)"
                        if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
                        once.finish(text)
                    } else {
                        once.finish(nil)
                    }
                case .failed, .cancelled:
                    once.finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { once.finish(nil) }
        }
    }
}

/// Resumes a lookup once, whichever comes first: an answer, a failure, or the timeout.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?
    private let connection: NWConnection

    init(_ continuation: CheckedContinuation<String?, Never>, connection: NWConnection) {
        self.continuation = continuation
        self.connection = connection
    }

    func finish(_ value: String?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        connection.cancel()
        pending.resume(returning: value)
    }
}

/// The pairing token, kept in the Keychain.
enum Keychain {
    private static let service = "com.shelbyklein.Chatterbox.mobile"

    static func save(_ key: String, _ value: String) {
        delete(key)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecValueData as String: Data(value.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecReturnData as String: true]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}
