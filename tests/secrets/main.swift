import Foundation
import Darwin

@MainActor func test() async throws {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw RuntimeFailure(message) }
        print("PASS \(message)")
    }
    let production = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Chatterbox")
    try check(!SecretVault.usesFixtureStorage(production), "production data-directory override selects Keychain")
    try check(!SecretVault.usesFixtureStorage(production.appendingPathComponent("../Chatterbox/")), "normalized production path selects Keychain")
    let alias = RuntimePaths.data.appendingPathComponent("production-alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: production)
    try check(!SecretVault.usesFixtureStorage(alias), "production symlink selects Keychain without reading any key")
    try check(SecretVault.usesFixtureStorage(RuntimePaths.data), "isolated data directory selects fixture storage")
    let writer = SecretVault()
    let service = SecretVault()
    let entry = SecretEntry(name: "Fixture API", variable: "FIXTURE_API")
    try writer.save(entry, value: "fixture-only-original-value")
    try check(!service.hasValue(entry), "separate service cache reproduces missing newly saved key")
    try service.reload()
    try check(service.hasValue(entry), "service reload receives saved value")
    let session = ChatSession(record: ConversationRecord(model: "default", effort: "", personality: .neutral))
    try check(service.environment(for: session)["FIXTURE_API"] == "fixture-only-original-value", "unscoped chat receives key in environment")
    try check(service.note(for: session)?.contains("$FIXTURE_API") == true && service.note(for: session)?.contains("fixture-only-original-value") == false, "agent note contains variable reference only")
    try check(service.redact("token=fixture-only-original-value") == "token=••••(FIXTURE_API)", "saved value redacted from transcript")
    let fingerprint = service.fingerprint(for: session)
    try writer.save(entry, value: "fixture-only-replacement-value")
    try service.reload()
    try check(service.fingerprint(for: session) != fingerprint, "key replacement changes next-launch fingerprint")
    var scoped = entry
    scoped.projects = [RuntimePaths.data.appendingPathComponent("project").path]
    try writer.save(scoped, value: nil)
    try service.reload()
    try check(service.environment(for: session).isEmpty, "project-only key excluded from unrelated chat")
    session.record.projectFolder = scoped.projects[0]
    try check(service.hasValue(scoped) && service.environment(for: session)["FIXTURE_API"] == "fixture-only-replacement-value", "scope edit keeps existing key and permits matching project")
    session.record.projectFolder = "/unrelated"
    session.record.sidechatProjectFolder = scoped.projects[0]
    try check(service.entries(for: session) == [scoped], "sidechat retains parent project secret scope")
    // Studios: every session in a chosen Studio, mixable with projects.
    let studio = UUID()
    let studioSession = ChatSession(record: ConversationRecord(model: "default", effort: "", personality: .neutral))
    studioSession.record.studioID = studio
    try check(service.environment(for: studioSession).isEmpty, "project-only key excluded from a Studio session")
    scoped.studios = [studio]
    try writer.save(scoped, value: nil)
    try service.reload()
    try check(service.environment(for: studioSession)["FIXTURE_API"] == "fixture-only-replacement-value", "Studio scope reaches the Studio's sessions")
    try check(service.entries(for: session) == [scoped], "mixed scope still reaches the chosen project")
    let otherStudio = ChatSession(record: ConversationRecord(model: "default", effort: "", personality: .neutral))
    otherStudio.record.studioID = UUID()
    try check(service.environment(for: otherStudio).isEmpty, "another Studio's sessions don't get it")
    let studioSidechat = ChatSession(record: ChatSession.sidechatRecord(of: studioSession, anchor: studioSession, number: 1))
    try check(service.entries(for: studioSidechat) == [scoped], "a Studio session's Sidechat follows its parent")
    scoped.projects = []
    try writer.save(scoped, value: nil)
    try service.reload()
    try check(service.environment(for: session).isEmpty && !service.entries(for: studioSession).isEmpty, "Studio-only key excludes project chats")
    let older = try JSONDecoder().decode(SecretEntry.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"Old","variable":"OLD","note":"","username":"","projects":[],"created":0}"#.utf8))
    try check(older.studios.isEmpty && older.isEverywhere, "entries saved before Studios still load")
    let revision = service.revision
    try service.reload()
    try check(service.revision == revision, "unchanged refresh does not publish a false change")
    let authorized = await service.authorize(entry.id)
    try check(authorized, "explicit authorization loads targeted fixture value")
    let unknown = await service.authorize(UUID())
    try check(!unknown, "unknown secret cannot be authorized")
    let metadata = RuntimePaths.data.appendingPathComponent("Secrets.json")
    let backup = try Data(contentsOf: metadata)
    try Data("malformed fixture".utf8).write(to: metadata)
    do { try service.reload(); throw RuntimeFailure("malformed metadata accepted") }
    catch is DecodingError { }
    try check(service.hasValue(entry), "failed metadata reload preserves last valid state")
    try backup.write(to: metadata)
    writer.remove(scoped)
    try service.reload()
    try check(service.environment(for: session).isEmpty && !service.hasValue(entry), "removal clears service cache and environment")
    try check(!FileManager.default.fileExists(atPath: RuntimePaths.data.appendingPathComponent("test-secret-\(entry.id.uuidString)").path), "removal cleans fixture value")
    print("PASS saved-secret storage selection, cross-process refresh, scope and privacy")
}

Task { @MainActor in
    do { try await test(); exit(0) }
    catch { print("FAIL \(error.localizedDescription)"); exit(1) }
}
RunLoop.main.run()
