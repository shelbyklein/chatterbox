import SwiftUI

/// Golem drawn live from his rig: five stones and two eyes on a Canvas, moved by `GolemPlayer`.
/// Square, transparent around him, on the same stage the old videos used (2.7 heads wide, his
/// base 85% of the way down), so he sits in the same spot. Changing `mood` plays the transition.
struct GolemRigView: View {
    let rig: GolemRig
    let mood: String
    @State private var player: GolemPlayer?
    @State private var clockStart = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSince(clockStart)
            if let player { GolemFrameCanvas(rig: rig, frame: player.frame(at: t)) }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            if player == nil { player = GolemPlayer(rig: rig, mood: mood) }
        }
        .onChange(of: mood) { _, newMood in
            player?.setMood(newMood, at: Date().timeIntervalSince(clockStart))
        }
        .accessibilityLabel("Golem, \(mood)")
    }
}

/// One moment of Golem, drawn: stones back to front by depth, the eyes on his head.
struct GolemFrameCanvas: View {
    let rig: GolemRig
    let frame: GolemFrame

    var body: some View {
        Canvas { context, size in draw(frame, in: &context, size: size) }
    }

    private func draw(_ frame: GolemFrame, in context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let unit = side / rig.spec.stage.size
        let ground = side * rig.spec.stage.groundFromTop
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        for (name, s) in frame.stones.sorted(by: { $0.value.depth > $1.value.depth }) {
            guard let stone = rig.spec.stones[name], let image = rig.images[name] else { continue }
            let w = stone.w, h = stone.h
            let sx = unit * s.scale * (1 + s.squash * 0.6), sy = unit * s.scale * (1 - s.squash)
            // Squash keeps the bottom of the stone where it was.
            let cy = s.y - h * s.scale * s.squash / 2
            var g = context
            g.translateBy(x: origin.x + side / 2 + s.x * unit, y: origin.y + ground - cy * unit)
            g.rotate(by: .degrees(-s.rot))
            g.scaleBy(x: sx, y: sy)
            if s.shade > 0 { g.addFilter(.colorMultiply(Color(white: 1 - s.shade))) }
            g.draw(Image(decorative: image, scale: 1).interpolation(.high), in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            if name == rig.spec.eyes.on {
                let open = max(0.08, 1 - frame.blink * 0.95)
                for (sprite, eye) in zip(rig.spec.eyes.sprites, rig.eyeImages) {
                    let ex = sprite.x - w / 2 + frame.eyeX
                    let ey = sprite.y - h / 2 + frame.eyeY + frame.blink * 4
                    let eh = sprite.h * open
                    g.draw(Image(decorative: eye, scale: 1).interpolation(.high),
                           in: CGRect(x: ex - sprite.w / 2, y: ey - eh / 2, width: sprite.w, height: eh))
                }
            }
        }
    }
}
