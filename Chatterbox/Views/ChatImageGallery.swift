import AppKit
import CryptoKit
import ImageIO
import SwiftUI

/// Every image made in a chat, newest first: images the agent generated, and screenshots,
/// renders, and proofs its replies pointed to. Clicking one opens it in the image viewer.
struct ChatImageGallery: View {
    let session: ChatSession
    let onOpen: (Attachment) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var images: [GalleryImage] = []
    @State private var loaded = false

    struct GalleryImage: Identifiable, Hashable {
        var id: String { url.path }
        var url: URL
        var date: Date
    }

    /// Images in the chat, found by scanning its replies. Files that are gone are skipped.
    static func collect(_ session: ChatSession) -> [GalleryImage] {
        let fm = FileManager.default
        var seen = Set<String>()
        var found: [GalleryImage] = []
        func add(_ url: URL) {
            guard MediaKind.isStillImage(url.path) || url.pathExtension.lowercased() == "gif",
                  seen.insert(url.path).inserted, fm.fileExists(atPath: url.path) else { return }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            found.append(GalleryImage(url: url, date: date))
        }
        for item in session.items {
            switch item.kind {
            case .image:
                item.attachments?.forEach { add($0.url) }
            case .assistant where item.phase == .final:
                ChatSession.referencedImages(in: item.text, folder: session.workingFolder).forEach(add)
            default:
                break
            }
        }
        return dedupe(found.reversed())
    }

    /// The generator's raw output and the copy the agent saved under a real name are often
    /// the same picture: keep one, preferring the named file. Only same-size files are hashed.
    private static func dedupe(_ images: [GalleryImage]) -> [GalleryImage] {
        func size(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1 }
        func generated(_ url: URL) -> Bool { url.lastPathComponent.hasPrefix("exec-") }
        let sizes = images.map { size($0.url) }
        let counts = Dictionary(sizes.map { ($0, 1) }, uniquingKeysWith: +)
        var kept: [String: Int] = [:]   // content key -> index in result
        var result: [GalleryImage] = []
        for (image, size) in zip(images, sizes) {
            guard size > 0, counts[size, default: 0] > 1, let data = try? Data(contentsOf: image.url) else { result.append(image); continue }
            let key = "\(size)-" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if let index = kept[key] {
                if generated(result[index].url), !generated(image.url) { result[index] = image }
            } else {
                kept[key] = result.count
                result.append(image)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Images in \u{201C}\(session.title)\u{201D}").font(.headline).lineLimit(1)
                if loaded { Text("\(images.count)").foregroundStyle(.secondary) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if images.isEmpty {
                ContentUnavailableView("No images yet", systemImage: "photo.on.rectangle",
                                       description: Text("Images the agent makes, and screenshots or renders it shows you, collect here."))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12)], spacing: 12) {
                        ForEach(images) { image in tile(image) }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 720, idealWidth: 960, minHeight: 520, idealHeight: 720)
        .task {
            images = Self.collect(session)
            loaded = true
        }
    }

    private func tile(_ image: GalleryImage) -> some View {
        Button {
            let attachment = Attachment(name: image.url.lastPathComponent, path: image.url.path,
                                        mediaType: "image/" + image.url.pathExtension.lowercased(), kind: .image)
            dismiss()
            // The viewer is a sheet too: open it once this one has gone.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onOpen(attachment) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                GalleryThumbnail(url: image.url)
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
                Text(image.url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                Text(image.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("View \(image.url.lastPathComponent)")
        .contextMenu {
            Button("Copy Image") { ImageClipboard.copy(image.url) }
            Button("Open in Preview") { NSWorkspace.shared.open(image.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([image.url]) }
        }
    }
}

/// A downsized thumbnail, loaded off the main thread.
private struct GalleryThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) {
            image = await Task.detached(priority: .utility) { () -> NSImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                              kCGImageSourceThumbnailMaxPixelSize: 600,
                                                                              kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
                else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }.value
        }
    }
}
