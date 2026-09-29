import AppKit
import SwiftUI

/// Renders one transcript row. Commentary is deliberately quiet so the final reply stands out.
struct ItemView: View {
    let item: DisplayItem
    /// True for the row the agent is working on right now.
    var isActive = false
    /// For user messages: the agent it went to, which picks the bubble color.
    var agent: Backend = .claude
    var onApproval: (UUID, DisplayItem.ApprovalState) -> Void = { _, _ in }
    var onAnswer: (UUID, [String: [String]]?) -> Void = { _, _ in }
    @Environment(\.readerStyle) private var style

    var body: some View {
        switch item.kind {
        case .user: userBubble
        case .assistant: assistantText
        case .thought: ThoughtView(text: item.text, isActive: isActive)
        case .tool: toolRow
        case .plan: PlanCard(steps: item.planSteps)
        case .notice: noticeRow
        case .approval: ApprovalCard(item: item) { onApproval(item.id, $0) }
        case .image: GeneratedImages(item: item)
        case .questions: QuestionCard(item: item, agent: agent) { onAnswer(item.id, $0) }
        }
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if item.queued == true {
                Label("Queued", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Sent while the agent is working. It joins the reply at the agent's next step.")
            } else if item.steered {
                Label("Sent while working", systemImage: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let attachments = item.attachments, !attachments.isEmpty {
                SentAttachments(attachments: attachments)
            }
            if !item.text.isEmpty {
                Text(item.text)
                    .font(style.body)
                    .lineSpacing(style.lineSpacing)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14).fill(style.color(for: agent).opacity(style.bubbleStrength)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 80)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var assistantText: some View {
        if item.phase == .commentary {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle().frame(width: 4, height: 4).foregroundStyle(.tertiary)
                Text(MarkdownText.inline(item.text, style: style))
                    .font(style.secondary)
                    .lineSpacing(style.lineSpacing)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else {
            MarkdownText(text: item.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var toolRow: some View {
        HStack(spacing: 7) {
            Group {
                switch item.toolState {
                case .running: ProgressView().controlSize(.small)
                case .done:
                    Image(systemName: "checkmark.circle").foregroundStyle(.green)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                case .failed:
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .frame(width: 16)
            Text(item.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .shimmering(item.toolState == .running)
        }
        .font(style.secondary)
        .foregroundStyle(.secondary)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: item.toolState)
    }

    private var noticeRow: some View {
        Text(item.text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}

private struct ApprovalCard: View {
    let item: DisplayItem
    let decide: (DisplayItem.ApprovalState) -> Void
    @Environment(\.cardFillsWidth) private var fillsWidth

    private var isPlan: Bool { item.approvalStyle == .plan }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(item.text, systemImage: "hand.raised")
                .font(.callout.weight(.medium))
            if let detail = item.detail, !detail.isEmpty {
                if isPlan {
                    ScrollView {
                        MarkdownText(text: detail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 320)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
                } else {
                    Text(detail)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(6)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
                }
            }
            switch item.approvalState ?? .expired {
            case .pending:
                HStack {
                    Button(isPlan ? "Start Building" : "Allow") { decide(.approved) }
                    Button(isPlan ? "Start and Accept Edits" : "Allow for This Chat") { decide(.approvedForSession) }
                    Button(isPlan ? "Keep Planning" : "Deny", role: .destructive) { decide(.denied) }
                }
                .controlSize(.small)
            case .approved:
                outcome(isPlan ? "Building, asking before edits" : "Allowed", "checkmark.circle", .green)
            case .approvedForSession:
                outcome(isPlan ? "Building, accepting edits" : "Allowed for this chat", "checkmark.circle", .green)
            case .denied:
                outcome(isPlan ? "Kept planning" : "Denied", "xmark.circle", .orange)
            case .expired:
                outcome("No longer needed", "clock", .secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: fillsWidth ? .infinity : 520, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.highlight.opacity(item.approvalState == .pending ? 0.6 : 0.2)))
    }

    private func outcome(_ text: String, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
    }
}

private struct ThoughtView: View {
    let text: String
    var isActive = false
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)
        } label: {
            Label(isActive ? "Thinking\u{2026}" : "Thought", systemImage: "sparkle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .shimmering(isActive)
        }
    }
}

private struct PlanCard: View {
    let steps: [PlanStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plan")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                HStack(spacing: 8) {
                    icon(for: step.status)
                    Text(step.step)
                        .strikethrough(step.status == "completed", color: .secondary)
                        .foregroundStyle(step.status == "completed" ? .secondary : .primary)
                        .fontWeight(step.status == "in_progress" ? .medium : .regular)
                }
                .font(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
        .animation(.easeInOut(duration: 0.2), value: steps)
    }

    @ViewBuilder
    private func icon(for status: String) -> some View {
        switch status {
        case "completed": Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case "in_progress": Image(systemName: "circle.dotted.circle").foregroundStyle(Color.highlight)
        default: Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }
}

/// Attachments on a sent message: images as previews, other files as chips. Click to open.
/// An image an agent made, shown in the reply. Click to open it for review.
private struct GeneratedImages: View {
    let item: DisplayItem
    @Environment(\.reviewImage) private var review

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(item.attachments ?? []) { image in
                if ["html", "htm", "svg"].contains(image.url.pathExtension.lowercased()) {
                    HTMLPreview(source: .file(image.url))
                } else {
                    picture(image)
                }
            }
            if !item.text.isEmpty {
                Text(item.text).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
            }
        }
    }

    private func picture(_ image: Attachment) -> some View {
                Button { review.open(image) } label: {
                    AttachmentThumbnail(attachment: image, size: 360)
                        .overlay(alignment: .bottomTrailing) {
                            Label("Review", systemImage: "pencil.and.scribble")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(8)
                        }
                }
                .buttonStyle(.plain)
                .help("Click to view larger and mark up")
                .contextMenu {
                    Button("Open in Preview") { NSWorkspace.shared.open(image.url) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([image.url]) }
                }
    }
}

private struct SentAttachments: View {
    let attachments: [Attachment]
    @Environment(\.reviewImage) private var review

    var body: some View {
        let images = attachments.filter { $0.kind == .image }
        let files = attachments.filter { $0.kind != .image }
        VStack(alignment: .trailing, spacing: 6) {
            if !images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(images) { image in
                        Button { review.open(image) } label: {
                            AttachmentThumbnail(attachment: image, size: images.count == 1 ? 240 : 120)
                        }
                        .buttonStyle(.plain)
                        .help(image.name)
                    }
                }
            }
            ForEach(files) { file in
                Button { NSWorkspace.shared.open(file.url) } label: {
                    HStack(spacing: 6) {
                        AttachmentThumbnail(attachment: file, size: 22)
                        Text(file.name).lineLimit(1).truncationMode(.middle)
                    }
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .help("Open \(file.name)")
            }
        }
    }
}

/// A square preview of an image attachment, or the file's icon for anything else.
struct AttachmentThumbnail: View {
    let attachment: Attachment
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if attachment.kind == .image, let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: size > 60 ? .fit : .fill)
                    .frame(maxWidth: size, maxHeight: size)
                    .frame(width: size > 60 ? nil : size, height: size > 60 ? nil : size)
                    .clipShape(RoundedRectangle(cornerRadius: size > 60 ? 10 : 5))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: attachment.path))
                    .resizable()
                    .frame(width: size, height: size)
            }
        }
        .task(id: attachment.path) {
            guard attachment.kind == .image else { return }
            let path = attachment.path
            image = await Task.detached { NSImage(contentsOfFile: path) }.value
        }
    }
}

/// A soft highlight that sweeps across text while the agent is working on it.
/// Core Animation runs the sweep, so SwiftUI does no work per frame. Off with Reduce Motion.
private struct Shimmer: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay { SheenView().mask(content).allowsHitTesting(false) }
        } else {
            content
        }
    }
}

/// A bright band sliding left to right, forever, drawn by a CAGradientLayer.
private struct SheenView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SheenNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SheenNSView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.colors = [NSColor.clear.cgColor, NSColor.white.withAlphaComponent(0.55).cgColor, NSColor.clear.cgColor]
        gradient.locations = [-0.4, -0.2, 0]
        layer?.addSublayer(gradient)

        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.4, -0.2, 0]
        sweep.toValue = [1, 1.2, 1.4]
        sweep.duration = 1.6
        sweep.repeatCount = .infinity
        gradient.add(sweep, forKey: "sweep")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }
}

extension View {
    func shimmering(_ active: Bool) -> some View { modifier(Shimmer(active: active)) }
}

/// Questions from the agent, one at a time: pick options or type an answer, then submit.
/// Once answered it shows a short summary of what you chose.
private struct QuestionCard: View {
    let item: DisplayItem
    /// The agent that asked, which picks the color of your answers' bubble.
    let agent: Backend
    let submit: ([String: [String]]?) -> Void
    @Environment(\.cardFillsWidth) private var fillsWidth
    @Environment(\.readerStyle) private var style

    @State private var index = 0
    @State private var picks: [String: Set<String>] = [:]
    @State private var other: [String: String] = [:]
    @FocusState private var otherFocused: Bool

    private var questions: [AgentQuestion] { item.questions ?? [] }

    var body: some View {
        if item.approvalState == .pending, questions.indices.contains(index) {
            asking(questions[index])
                .padding(14)
                .frame(maxWidth: fillsWidth ? .infinity : 560, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.highlight.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.highlight.opacity(0.5)))
        } else {
            answered
        }
    }

    private func asking(_ question: AgentQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(question.header.isEmpty ? "Question" : question.header, systemImage: "questionmark.bubble")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.highlight)
                Spacer()
                if questions.count > 1 {
                    Text("\(index + 1) of \(questions.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(question.question).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            if question.multiSelect {
                Text("Choose any that apply").font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { number, option in
                    optionRow(option, number: number + 1, question: question)
                }
            }

            Group {
                if question.isSecret {
                    SecureField("Type your answer", text: binding(for: question))
                } else {
                    TextField(question.options.isEmpty ? "Type your answer" : "Other\u{2026}", text: binding(for: question), axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .textFieldStyle(.roundedBorder)
            .focused($otherFocused)
            .onSubmit(advance)

            HStack {
                Button("Skip") { submit(nil) }.help("Don't answer; the agent carries on without these")
                Spacer()
                if index > 0 { Button("Back") { index -= 1 } }
                Button(index == questions.count - 1 ? "Submit" : "Next", action: advance)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(HighlightButtonStyle())
                    .disabled(answer(for: question).isEmpty)
            }
            .controlSize(.small)
        }
        .id(question.id)
    }

    private func optionRow(_ option: AgentQuestion.Option, number: Int, question: AgentQuestion) -> some View {
        let selected = picks[question.id, default: []].contains(option.label)
        return Button {
            var set = picks[question.id, default: []]
            if question.multiSelect {
                if selected { set.remove(option.label) } else { set.insert(option.label) }
            } else {
                set = selected ? [] : [option.label]
            }
            // Selecting only marks the choice; Next or Submit sends it.
            picks[question.id] = set
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: question.multiSelect ? (selected ? "checkmark.square.fill" : "square") : (selected ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(selected ? Color.highlight : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                    if !option.detail.isEmpty, option.detail != option.label {
                        Text(option.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.highlight.opacity(0.14) : Color.primary.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Your answers, styled and placed like your own messages: right-aligned, in the bubble
    /// color of the agent that asked.
    private var answered: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Label(item.approvalState == .approved ? "Answered" : item.approvalState == .denied ? "Skipped" : "No longer needed",
                  systemImage: item.approvalState == .approved ? "checkmark.circle" : "questionmark.bubble")
                .font(.caption2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(questions) { question in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(question.question).font(style.secondary).foregroundStyle(.secondary)
                        if let answer = item.answers?[question.id] {
                            Text(question.isSecret ? "\u{2022}\u{2022}\u{2022}\u{2022}" : answer.joined(separator: ", "))
                                .font(style.body.weight(.medium))
                        }
                    }
                }
            }
            .lineSpacing(style.lineSpacing)
            .textSelection(.enabled)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14).fill(style.color(for: agent).opacity(style.bubbleStrength)))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 80)
        .padding(.top, 6)
    }

    private func binding(for question: AgentQuestion) -> Binding<String> {
        Binding(get: { other[question.id] ?? "" }, set: { other[question.id] = $0 })
    }

    /// Picked options, plus anything typed.
    private func answer(for question: AgentQuestion) -> [String] {
        let chosen = question.options.map(\.label).filter { picks[question.id, default: []].contains($0) }
        let typed = (other[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return chosen + (typed.isEmpty ? [] : [typed])
    }

    private func advance() {
        guard questions.indices.contains(index), !answer(for: questions[index]).isEmpty else { return }
        if index < questions.count - 1 {
            index += 1
        } else {
            submit(Dictionary(uniqueKeysWithValues: questions.map { ($0.id, answer(for: $0)) }))
        }
    }
}

/// Cards in the tray above the message box span its full width instead of their usual cap.
private struct CardFillsWidthKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var cardFillsWidth: Bool {
        get { self[CardFillsWidthKey.self] }
        set { self[CardFillsWidthKey.self] = newValue }
    }
}
