import AppKit
import SwiftUI

/// Markdown renderer for replies: headings, paragraphs, bulleted and numbered lists,
/// tables, quotes, rules, and fenced code, with inline bold, italics, code, and links.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
    }

    // MARK: - Blocks

    enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case list(items: [ListItem])
        case table(header: [String], rows: [[String]], alignments: [HorizontalAlignment])
        case quote(String)
        case rule
        case code(String, language: String)
    }

    struct ListItem {
        var marker: String      // "•" or "3."
        var depth: Int
        var text: String
    }

    static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var list: [ListItem] = []
        var quote: [String] = []
        let lines = text.components(separatedBy: "\n")
        var index = 0

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
            if !list.isEmpty { blocks.append(.list(items: list)); list = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))); quote = [] }
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code; an unterminated fence is still streaming, so show it anyway.
            if trimmed.hasPrefix("```") {
                flush()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(code.joined(separator: "\n"), language: language))
                index += 1
                continue
            }

            if trimmed.isEmpty { flush(); index += 1; continue }

            if let match = trimmed.firstMatch(of: #/^(#{1,6})\s+(.+?)\s*#*$/#) {
                flush()
                blocks.append(.heading(level: match.1.count, text: String(match.2)))
                index += 1
                continue
            }

            if trimmed.firstMatch(of: #/^([-*_])(\s*\1){2,}$/#) != nil {
                flush()
                blocks.append(.rule)
                index += 1
                continue
            }

            // A table is a pipe row followed by a separator row like |---|:--:|.
            if trimmed.hasPrefix("|") || trimmed.contains(" | "), index + 1 < lines.count,
               let alignments = tableAlignments(lines[index + 1]) {
                flush()
                let header = tableCells(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard row.contains("|"), !row.isEmpty else { break }
                    rows.append(tableCells(row))
                    index += 1
                }
                let width = max(header.count, rows.map(\.count).max() ?? 0)
                let pad = { (cells: [String]) in cells + Array(repeating: "", count: max(0, width - cells.count)) }
                blocks.append(.table(header: pad(header), rows: rows.map(pad),
                                     alignments: alignments + Array(repeating: .leading, count: max(0, width - alignments.count))))
                continue
            }

            if trimmed.hasPrefix(">") {
                if !paragraph.isEmpty || !list.isEmpty { flush() }
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                index += 1
                continue
            }

            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            if let match = trimmed.firstMatch(of: #/^[-*+•]\s+(.*)$/#) {
                if !paragraph.isEmpty || !quote.isEmpty { flush() }
                list.append(ListItem(marker: "\u{2022}", depth: indent / 2, text: String(match.1)))
                index += 1
                continue
            }
            if let match = trimmed.firstMatch(of: #/^(\d{1,3})[.)]\s+(.*)$/#) {
                if !paragraph.isEmpty || !quote.isEmpty { flush() }
                list.append(ListItem(marker: "\(match.1).", depth: indent / 2, text: String(match.2)))
                index += 1
                continue
            }

            // A wrapped continuation of the previous list item.
            if !list.isEmpty, indent >= 2 {
                list[list.count - 1].text += " " + trimmed
                index += 1
                continue
            }
            if !list.isEmpty || !quote.isEmpty { flush() }
            paragraph.append(line)
            index += 1
        }
        flush()
        return blocks
    }

    static func tableCells(_ row: String) -> [String] {
        var body = row.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        // Split on pipes that aren't escaped (\|) or inside inline code.
        var cells: [String] = []
        var current = ""
        var inCode = false
        var previous: Character = " "
        for char in body {
            if char == "`" { inCode.toggle() }
            if char == "|", !inCode, previous != "\\" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
            previous = char
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells.map { $0.replacingOccurrences(of: "\\|", with: "|") }
    }

    /// The column alignments if `line` is a table separator row, else nil.
    static func tableAlignments(_ line: String) -> [HorizontalAlignment]? {
        let cells = tableCells(line)
        guard !cells.isEmpty, line.contains("-"),
              cells.allSatisfy({ $0.firstMatch(of: #/^:?-{1,}:?$/#) != nil }) else { return nil }
        return cells.map { cell in
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): return .center
            case (false, true): return .trailing
            default: return .leading
            }
        }
    }

    // MARK: - Inline

    /// Bold, italics, links, and code spans. Code gets a subtle chip.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var result = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        for run in result.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                result[run.range].font = .system(.callout, design: .monospaced)
                result[run.range].backgroundColor = Color.primary.opacity(0.09)
            }
            if run.link != nil {
                result[run.range].foregroundColor = .accentColor
                result[run.range].underlineStyle = .single
            }
        }
        return result
    }
}

// MARK: - Views

private struct BlockView: View {
    let block: MarkdownText.Block

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownText.inline(text))
                .font(level == 1 ? .title2.weight(.semibold) : level == 2 ? .title3.weight(.semibold) : .headline)
                .padding(.top, level <= 2 ? 6 : 2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let text):
            Text(MarkdownText.inline(text))
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .list(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(item.marker)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(minWidth: item.marker == "\u{2022}" ? 10 : 20, alignment: .trailing)
                        Text(MarkdownText.inline(item.text))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.depth) * 18)
                }
            }

        case .table(let header, let rows, let alignments):
            TableView(header: header, rows: rows, alignments: alignments)

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(.tertiary).frame(width: 3)
                Text(MarkdownText.inline(text))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .rule:
            Divider().padding(.vertical, 4)

        case .code(let code, let language):
            CodeBlock(code: code, language: language)
        }
    }
}

private struct TableView: View {
    let header: [String]
    let rows: [[String]]
    let alignments: [HorizontalAlignment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(header.indices, id: \.self) { column in
                        cell(header[column], column: column).fontWeight(.semibold)
                    }
                }
                .background(Color.primary.opacity(0.06))
                ForEach(rows.indices, id: \.self) { row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(header.indices, id: \.self) { column in
                            cell(rows[row][column], column: column)
                        }
                    }
                    .background(row.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func cell(_ text: String, column: Int) -> some View {
        let alignment = alignments[column]
        return Text(MarkdownText.inline(text))
            .font(.callout)
            .multilineTextAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
            .textSelection(.enabled)
            .frame(minWidth: 40, maxWidth: 360, alignment: Alignment(horizontal: alignment, vertical: .center))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .gridColumnAlignment(alignment)
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
