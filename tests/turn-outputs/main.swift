import AppKit
import SwiftUI

// What a turn made, shown under its reply (TurnOutputs; Shelby, November 24): media changed
// while it ran, web media it linked (copied locally), on the Mac and in what the phone gets.

var failures = 0
func check(_ ok: Bool, _ what: String) { print((ok ? "PASS: " : "FAIL: ") + what); if !ok { failures += 1 } }

/// Web files, served without a network.
final class StubWeb: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "media.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        let (type, body): (String, Data) = path.hasSuffix(".png") || path.contains("render")
            ? ("image/png", png()) : path.hasSuffix(".pdf") ? ("application/pdf", Data("%PDF-1.4\n".utf8)) : ("text/html", Data("<html>".utf8))
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func png(_ color: NSColor = .systemPink) -> Data {
    let image = NSImage(size: NSSize(width: 64, height: 40)); image.lockFocus(); color.setFill(); NSRect(x: 0, y: 0, width: 64, height: 40).fill(); image.unlockFocus()
    return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
}

@MainActor func run() async throws {
    URLProtocol.registerClass(StubWeb.self)
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("turn-outputs-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("out/deep/er/still/deeper"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let old = Date().addingTimeInterval(-3600)
    func write(_ path: String, _ data: Data = png(), date: Date? = nil) throws -> String {
        let url = root.appendingPathComponent(path)
        try data.write(to: url)
        if let date { try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        return TurnOutputs.normal(url.path)
    }
    let started = Date().addingTimeInterval(-60)
    _ = try write("before.png", date: old)
    let banner = try write("out/banner.png")
    let proof = try write("out/proof.pdf", Data("%PDF-1.4\n".utf8))
    _ = try write("notes.txt", Data("text".utf8))
    _ = try write("node_modules/icon.png")
    _ = try write("out/deep/er/still/deeper/too-deep.png")

    // The scan: media changed since the turn began, not old files, text, dependencies or too deep.
    let found = TurnOutputs.scan(folders: [root.path], since: started).map(\.path)
    check(Set(found) == [banner, proof], "the scan finds the media changed during the turn, nothing old, plain, in node_modules or too deep: \(found.map { ($0 as NSString).lastPathComponent })")
    // Choosing: named files always; the rest only when there are a few.
    let many = (1...5).map { (path: "/x/other\($0).png", date: Date()) }
    check(TurnOutputs.choose(many + [(banner, Date())], mentioned: "Writing banner.png", generated: nil) == [banner],
          "in a busy folder only what the turn's rows mention is kept")
    check(TurnOutputs.choose([(banner, Date()), (proof, Date())], mentioned: "", generated: nil) == [banner, proof], "a few unmentioned files are kept")
    check(TurnOutputs.choose(many, mentioned: "", generated: "/x/") .count == 5, "Codex's generated images are always kept")

    // Web media: by file name or as a Markdown image; pages aren't.
    let text = "Here it is: https://media.test/out/render?id=4 and ![shot](https://media.test/render?x=1) plus https://media.test/a/poster.png, https://media.test/doc.pdf and https://example.com/page"
    let links = TurnOutputs.webMedia(in: text)
    check(links.map(\.absoluteString) == ["https://media.test/render?x=1", "https://media.test/a/poster.png", "https://media.test/doc.pdf"],
          "web pictures and PDFs are found by name or Markdown image, not pages: \(links)")
    let cache = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("reply-media-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: cache) }
    let copies = await TurnOutputs.download(links + [URL(string: "https://media.test/page.html")!], folder: cache)
    check(copies.count == 3 && copies.allSatisfy { fm.fileExists(atPath: $0) } && copies.first?.hasSuffix(".png") == true && copies.last?.hasSuffix(".pdf") == true,
          "web media are copied locally, a page isn't: \(copies.map { ($0 as NSString).lastPathComponent })")
    let again = await TurnOutputs.download(links, folder: cache)
    check(again == copies, "a copy already kept is reused")

    // At turn end: the final reply gets what the turn made, minus what it names.
    var record = ConversationRecord(model: "default", effort: "", personality: .friendly)
    record.codex = CodexSettings(folder: root.path, canEdit: false, mode: "fullAccess")
    record.activeBackend = .claude
    record.items = [DisplayItem(kind: .user, timestamp: started.addingTimeInterval(1), text: "Make the banner"),
                    DisplayItem(kind: .tool, timestamp: started.addingTimeInterval(2), text: "Writing banner.png"),
                    DisplayItem(kind: .assistant, timestamp: Date(), text: "Done. Proof: `\(proof)` and the render at https://media.test/a/poster.png", phase: .final)]
    let session = ChatSession(record: record)
    session.noteTurnOutputs(since: started)
    let deadline = Date().addingTimeInterval(10)
    while session.record.items.last?.made == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
    let made = session.record.items.last?.made ?? []
    check(made.contains(banner) && !made.contains(proof) && made.filter { $0.contains("Reply Media") }.count == 1 && Set(made).count == made.count,
          "the reply gets the banner it didn't name and the web render's copy, not the PDF it named: \(made.map { ($0 as NSString).lastPathComponent })")
    let shown = ChatSession.madeFiles(session.record.items.last!, folder: root.path)
    check(shown.images.contains(URL(fileURLWithPath: banner)) && shown.documents.isEmpty, "shown under it: the made pictures, minus what it names")
    // What the phone gets: the made files as attachments it can fetch.
    let finalItem: DisplayItem = session.record.items.last!
    let mapped: Companion.Item = CompanionMapper.item(finalItem, folder: root.path)
    check(mapped.attachments.contains { $0.id == ChatSession.mediaID(banner) && $0.isImage }, "the phone gets the banner as a picture")

    // The strip, rendered.
    let view = MadeThisTurn(images: [URL(fileURLWithPath: banner)], media: [], documents: [URL(fileURLWithPath: proof)])
        .padding(16).frame(width: 560).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: view); renderer.scale = 2
    if let image = renderer.cgImage, CommandLine.arguments.count > 1 {
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        check(image.height > 100, "the Made this turn strip renders (\(image.width)x\(image.height))")
    } else { check(false, "the strip renders") }
    print(failures == 0 ? "All turn output checks passed" : "\(failures) failed")
    exit(failures == 0 ? 0 : 1)
}

Task { @MainActor in do { try await run() } catch { print("FAIL: \(error)"); exit(1) } }
RunLoop.main.run()
