import AppKit
import SwiftUI

/// Lightweight Markdown renderer: fenced code blocks, headings, bullets, and inline styles.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.segments(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .prose(let prose):
                    ForEach(Array(Self.paragraphs(prose).enumerated()), id: \.offset) { _, paragraph in
                        Text(Self.inline(Self.blockStyled(paragraph)))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .code(let code, let language):
                    CodeBlock(code: code, language: language)
                }
            }
        }
    }

    enum Segment { case prose(String), code(String, String) }

    static func segments(_ text: String) -> [Segment] {
        var result: [Segment] = []
        var buffer: [String] = []
        var inCode = false
        var language = ""
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    result.append(.code(buffer.joined(separator: "\n"), language))
                } else if !buffer.isEmpty {
                    result.append(.prose(buffer.joined(separator: "\n")))
                }
                buffer = []
                language = inCode ? "" : String(line.trimmingCharacters(in: .whitespaces).dropFirst(3))
                inCode.toggle()
            } else {
                buffer.append(line)
            }
        }
        if !buffer.isEmpty {
            // An unterminated fence is still streaming; show it as code anyway.
            result.append(inCode ? .code(buffer.joined(separator: "\n"), language) : .prose(buffer.joined(separator: "\n")))
        }
        return result
    }

    static func paragraphs(_ prose: String) -> [String] {
        prose.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Converts block-level syntax the inline parser doesn't handle.
    static func blockStyled(_ paragraph: String) -> String {
        paragraph.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = trimmed.firstMatch(of: #/^#{1,6}\s+(.+)$/#) {
                return "**\(match.1)**"
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let indent = String(repeating: "    ", count: (line.count - line.drop(while: { $0 == " " }).count) / 2)
                return indent + "\u{2022} " + trimmed.dropFirst(2)
            }
            return line
        }.joined(separator: "\n")
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct CodeBlock: View {
    let code: String
    let language: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }
}
