import AVKit
import SwiftUI

/// A GIF, video, or Lottie animation in the chat, playing. Videos loop silently with
/// controls; Open shows the file in its own app.
struct MediaPreview: View {
    let url: URL
    let kind: MediaKind

    var body: some View {
        Group {
            switch kind {
            case .animatedImage: AnimatedImage(url: url)
            case .video: LoopingVideo(url: url)
            case .lottie: lottie { (try? String(contentsOf: url, encoding: .utf8)).map(MediaKind.lottiePage(json:)) }
            case .dotLottie: lottie { (try? Data(contentsOf: url)).map { MediaKind.dotLottiePage(base64: $0.base64EncodedString()) } }
            }
        }
        // Bottom corner: a page preview keeps its own buttons at the top.
        .overlay(alignment: .bottomTrailing) {
            Button { NSWorkspace.shared.open(url) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(6)
                .help("Open \(url.lastPathComponent)")
        }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    @ViewBuilder
    private func lottie(_ page: () -> String?) -> some View {
        if let page = page() {
            // Near the animation's own size, not the reply's full width.
            HTMLPreview(source: .html(page), maxHeight: 400).frame(maxWidth: 420)
        } else {
            Text("Couldn't read \(url.lastPathComponent).").foregroundStyle(.secondary)
        }
    }
}

/// A GIF that animates, at its own size (up to 480 points).
private struct AnimatedImage: View {
    let url: URL
    @State private var size: CGSize?

    var body: some View {
        AnimatedImageView(url: url)
            .frame(width: size.map { min($0.width, 480) }, height: size.map { min($0.width, 480) * $0.height / max($0.width, 1) })
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .task(id: url) { size = NSImage(contentsOf: url)?.size }
    }
}

private struct AnimatedImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        view.canDrawSubviewsIntoLayer = true
        view.image = NSImage(contentsOf: url)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {}
}

/// A video that plays muted and loops, with the usual controls, at the video's own shape.
private struct LoopingVideo: View {
    let url: URL
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var aspect: CGFloat = 16 / 9

    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: 640, maxHeight: 480)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .task(id: url) {
                let item = AVPlayerItem(url: url)
                let queue = AVQueuePlayer()
                queue.isMuted = true
                looper = AVPlayerLooper(player: queue, templateItem: item)
                player = queue
                queue.play()
                if let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
                   let natural = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform) {
                    let shown = natural.applying(transform)
                    if abs(shown.height) > 0 { aspect = abs(shown.width) / abs(shown.height) }
                }
            }
            .onDisappear { player?.pause() }
    }
}
