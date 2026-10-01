#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// How the transcript reads: font, sizes, and spacing, chosen in Settings → Appearance.
struct ReaderStyle: Equatable {
    var textSize: CGFloat = 13
    var lineSpacing: CGFloat = 3
    var paragraphSpacing: CGFloat = 10
    var codeSize: CGFloat = 12
    var contentWidth: CGFloat = 820
    var design: Font.Design = .default
    /// Each agent's color: your message bubbles, the message box, and the model line.
    var claudeColor: Color = ReaderStyle.bubbleColor(ReaderStyle.claudeDefault)
    var codexColor: Color = ReaderStyle.bubbleColor(ReaderStyle.codexDefault)
    var bubbleStrength: Double = 0.18
    /// Tighter spacing for step rows, notes, and thinking.
    var compactSteps = false
    var showThinking = true

    static let defaults = ReaderStyle()
    static let claudeDefault = "#D97757"
    static let codexDefault = "#10A37F"

    func color(for backend: Backend) -> Color { backend == .claude ? claudeColor : codexColor }

    var body: Font { .system(size: textSize, design: design) }
    /// Status rows, commentary, and table cells: a step below the body.
    var secondary: Font { .system(size: textSize - 1, design: design) }
    var code: Font { .system(size: codeSize, design: .monospaced) }

    func heading(_ level: Int) -> Font {
        let scale: CGFloat = level == 1 ? 1.45 : level == 2 ? 1.25 : 1.08
        return .system(size: (textSize * scale).rounded(), weight: .semibold, design: design)
    }

    static let designs: [(id: String, label: String, design: Font.Design)] = [
        ("default", "System", .default),
        ("rounded", "Rounded", .rounded),
        ("serif", "Serif", .serif),
        ("monospaced", "Monospaced", .monospaced),
    ]

    static func design(_ id: String) -> Font.Design {
        designs.first { $0.id == id }?.design ?? .default
    }

    static let bubbleColors: [(id: String, label: String, color: Color)] = [
        (claudeDefault, "Clay", bubbleColor(claudeDefault)), (codexDefault, "Green", bubbleColor(codexDefault)),
        ("accent", "Accent", .accentColor), ("blue", "Blue", .blue), ("purple", "Purple", .purple),
        ("pink", "Pink", .pink), ("orange", "Orange", .orange),
        ("teal", "Teal", .teal), ("gray", "Gray", .gray),
    ]

    /// A preset id, or "#RRGGBB" for a custom color.
    static func bubbleColor(_ id: String) -> Color {
        if id.hasPrefix("#"), let value = Int(id.dropFirst(), radix: 16) {
            return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                         blue: Double(value & 0xFF) / 255)
        }
        return bubbleColors.first { $0.id == id }?.color ?? .accentColor
    }

    static func hex(_ color: Color) -> String {
        #if canImport(AppKit)
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #endif
    }
}

private struct ReaderStyleKey: EnvironmentKey {
    static let defaultValue = ReaderStyle.defaults
}

extension EnvironmentValues {
    var readerStyle: ReaderStyle {
        get { self[ReaderStyleKey.self] }
        set { self[ReaderStyleKey.self] = newValue }
    }
}

/// Reads the Appearance settings, so any view can build the current style.
struct ReaderStyleSettings: DynamicProperty {
    @AppStorage("readerTextSize") var textSize = Double(ReaderStyle.defaults.textSize)
    @AppStorage("readerLineSpacing") var lineSpacing = Double(ReaderStyle.defaults.lineSpacing)
    @AppStorage("readerParagraphSpacing") var paragraphSpacing = Double(ReaderStyle.defaults.paragraphSpacing)
    @AppStorage("readerCodeSize") var codeSize = Double(ReaderStyle.defaults.codeSize)
    @AppStorage("readerContentWidth") var contentWidth = Double(ReaderStyle.defaults.contentWidth)
    @AppStorage("readerFontDesign") var design = "default"
    @AppStorage("readerClaudeColor") var claudeColor = ReaderStyle.claudeDefault
    @AppStorage("readerCodexColor") var codexColor = ReaderStyle.codexDefault
    @AppStorage("readerBubbleStrength") var bubbleStrength = ReaderStyle.defaults.bubbleStrength
    @AppStorage("readerCompactSteps") var compactSteps = false
    @AppStorage("readerShowThinking") var showThinking = true

    var style: ReaderStyle {
        ReaderStyle(textSize: textSize, lineSpacing: lineSpacing, paragraphSpacing: paragraphSpacing,
                    codeSize: codeSize, contentWidth: contentWidth, design: ReaderStyle.design(design),
                    claudeColor: ReaderStyle.bubbleColor(claudeColor), codexColor: ReaderStyle.bubbleColor(codexColor),
                    bubbleStrength: bubbleStrength,
                    compactSteps: compactSteps, showThinking: showThinking)
    }

    func reset() {
        let d = ReaderStyle.defaults
        textSize = d.textSize
        lineSpacing = d.lineSpacing
        paragraphSpacing = d.paragraphSpacing
        codeSize = d.codeSize
        contentWidth = d.contentWidth
        design = "default"
        claudeColor = ReaderStyle.claudeDefault
        codexColor = ReaderStyle.codexDefault
        bubbleStrength = d.bubbleStrength
        compactSteps = false
        showThinking = true
    }
}

extension Color {
    /// Chatterbox's own highlight: selection, progress, and emphasis. White in dark mode and
    /// black in light mode, instead of the system's blue accent.
    static let highlight = Color.primary
}

/// The main button in a card (Submit, Next): filled with the highlight, text in the
/// background color, so it reads as primary without the system's blue.
struct HighlightButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .foregroundStyle(Color.windowBackground)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.highlight.opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.3)))
    }
}

extension Color {
    /// The window's own background, on either platform.
    static var windowBackground: Color {
        #if canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}
