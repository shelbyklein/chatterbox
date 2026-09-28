import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A file the user attached to a message. The file is copied into Application Support,
/// so the chat keeps working if the original moves.
struct Attachment: Codable, Identifiable, Equatable, Hashable {
    enum Kind: String, Codable { case image, pdf, text, document, other }

    var id = UUID()
    var name: String
    /// The app's own copy of the file.
    var path: String
    var mediaType: String
    var kind: Kind
    /// Set once the file is uploaded to the Anthropic Files API, so it can be deleted with the chat.
    var claudeFileID: String?

    var url: URL { URL(fileURLWithPath: path) }
}

/// What the user sent: text plus any attachments. Also used for messages sent mid-turn.
struct UserMessage {
    var text: String
    var attachments: [Attachment] = []
}

enum Attachments {
    /// Claude resizes anything larger, so sending more only costs upload time.
    static let maxImageEdge = 2576
    static let maxImageBytes = 5 * 1024 * 1024
    static let maxTextBytes = 2 * 1024 * 1024

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Chatterbox/Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Import

    /// Copies a file into the attachment store, converting images Claude can't read (HEIC, TIFF, …).
    static func importFile(_ source: URL) throws -> Attachment {
        let type = UTType(filenameExtension: source.pathExtension) ?? .data
        if type.conforms(to: .image) {
            return try importImage(at: source, name: source.deletingPathExtension().lastPathComponent)
        }
        let id = UUID()
        let dest = try folder(for: id).appendingPathComponent(safeName(source.lastPathComponent))
        try FileManager.default.copyItem(at: source, to: dest)
        return Attachment(id: id, name: source.lastPathComponent, path: dest.path,
                          mediaType: type.preferredMIMEType ?? "application/octet-stream", kind: kind(of: type, at: dest))
    }

    /// Imports raw image data, such as a pasted screenshot.
    static func importImageData(_ data: Data, name: String = "Pasted image") throws -> Attachment {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        return try importImage(at: temp, name: name)
    }

    private static func importImage(at source: URL, name: String) throws -> Attachment {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            throw AttachmentError("\(name) isn't an image macOS can read.")
        }
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let sourceType = (CGImageSourceGetType(src) as String?).flatMap(UTType.init) ?? .image
        let native: [UTType] = [.png, .jpeg, .gif, .webP]
        let id = UUID()
        let folder = try folder(for: id)

        // Already fine as-is: keep the original bytes.
        if native.contains(sourceType), max(width, height) <= maxImageEdge, size <= maxImageBytes {
            let ext = sourceType.preferredFilenameExtension ?? "png"
            let dest = folder.appendingPathComponent(safeName(name) + "." + ext)
            try FileManager.default.copyItem(at: source, to: dest)
            return Attachment(id: id, name: dest.lastPathComponent, path: dest.path,
                              mediaType: sourceType.preferredMIMEType ?? "image/png", kind: .image)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height, 1), maxImageEdge),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            throw AttachmentError("Couldn't convert \(name).")
        }
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let outType: UTType = hasAlpha ? .png : .jpeg
        let dest = folder.appendingPathComponent(safeName(name) + "." + (outType.preferredFilenameExtension ?? "png"))
        guard let out = CGImageDestinationCreateWithURL(dest as CFURL, outType.identifier as CFString, 1, nil) else {
            throw AttachmentError("Couldn't convert \(name).")
        }
        CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(out) else { throw AttachmentError("Couldn't convert \(name).") }
        return Attachment(id: id, name: dest.lastPathComponent, path: dest.path,
                          mediaType: outType.preferredMIMEType ?? "image/png", kind: .image)
    }

    private static func kind(of type: UTType, at url: URL) -> Attachment.Kind {
        if type.conforms(to: .pdf) { return .pdf }
        if [UTType.rtf, .rtfd, .html, .webArchive].contains(where: type.conforms(to:))
            || ["doc", "docx", "odt"].contains(url.pathExtension.lowercased()) {
            return .document
        }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) || isUTF8Text(url) { return .text }
        return .other
    }

    private static func isUTF8Text(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let sample = (try? handle.read(upToCount: 8192)) ?? Data()
        return !sample.contains(0) && String(data: sample, encoding: .utf8) != nil
    }

    private static func folder(for id: UUID) throws -> URL {
        let url = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// File names the Files API accepts: no path separators or reserved characters.
    static func safeName(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "<>:\"|?*\\/").union(.controlCharacters)
        let cleaned = String(name.unicodeScalars.map { bad.contains($0) ? "_" : Character($0) }).prefix(200)
        return cleaned.isEmpty ? "file" : String(cleaned)
    }

    static func remove(_ attachments: [Attachment]) {
        for attachment in attachments {
            try? FileManager.default.removeItem(at: attachment.url.deletingLastPathComponent())
        }
    }

    // MARK: - Pasteboard

    /// Attachments on the pasteboard: copied files first, otherwise image data (screenshots, copied images).
    /// Returns nil when the pasteboard holds nothing to attach, so a normal text paste proceeds.
    @MainActor
    static func fromPasteboard(_ pasteboard: NSPasteboard = .general) -> [Attachment]? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return urls.compactMap { try? importFile($0) }
        }
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier),
                                                         NSPasteboard.PasteboardType(UTType.heic.identifier)]
        // Rich text copied from a page can carry an image too; paste that as text.
        guard pasteboard.string(forType: .string) == nil,
              let type = pasteboard.availableType(from: imageTypes),
              let data = pasteboard.data(forType: type) else { return nil }
        return (try? importImageData(data)).map { [$0] }
    }

    // MARK: - Claude content blocks

    /// Content blocks for Claude: images and PDFs go through the Files API, text is inlined.
    /// Returns the blocks and the attachments updated with their uploaded file IDs.
    static func claudeBlocks(for attachments: [Attachment], client: AnthropicClient) async throws -> ([JSON], [Attachment]) {
        var blocks: [JSON] = []
        var updated: [Attachment] = []
        for var attachment in attachments {
            switch attachment.kind {
            case .image, .pdf:
                let fileID: String
                if let existing = attachment.claudeFileID {
                    fileID = existing
                } else {
                    fileID = try await client.uploadFile(attachment.url, name: safeName(attachment.name), mediaType: attachment.mediaType)
                }
                attachment.claudeFileID = fileID
                if attachment.kind == .image {
                    blocks.append(["type": "image", "source": ["type": "file", "file_id": .string(fileID)]])
                } else {
                    blocks.append(["type": "document", "source": ["type": "file", "file_id": .string(fileID)],
                                   "title": .string(attachment.name)])
                }
            case .text, .document:
                blocks.append(.text("<attachment name=\"\(attachment.name)\">\n\(try readText(attachment))\n</attachment>"))
            case .other:
                throw AttachmentError("Claude can't read \(attachment.name). Try a PDF, image, or text file.")
            }
            updated.append(attachment)
        }
        return (blocks, updated)
    }

    private static func readText(_ attachment: Attachment) throws -> String {
        let size = (try? attachment.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if attachment.kind == .document {
            // Word, RTF, and HTML documents, converted to plain text by AppKit.
            let text = try NSAttributedString(url: attachment.url, options: [:], documentAttributes: nil).string
            return text
        }
        guard size <= maxTextBytes else {
            throw AttachmentError("\(attachment.name) is too large to include as text (limit 2 MB).")
        }
        let data = try Data(contentsOf: attachment.url)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}

struct AttachmentError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension AnthropicClient {
    /// POST /v1/files. Returns the file ID.
    func uploadFile(_ url: URL, name: String, mediaType: String) async throws -> String {
        let boundary = "chatterbox-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: \(mediaType)\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: url))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/files")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSON.parse(data)
        guard status == 200, let id = json?["id"]?.string else {
            throw APIError(status: status, type: json?["error"]?["type"]?.string,
                           message: "Couldn't upload \(name): " + (json?["error"]?["message"]?.string ?? "HTTP \(status)"))
        }
        return id
    }

    /// DELETE /v1/files/{id}. Best effort; used when a chat is deleted.
    func deleteFile(_ id: String) async {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/files/\(id)")!)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        _ = try? await URLSession.shared.data(for: request)
    }
}
