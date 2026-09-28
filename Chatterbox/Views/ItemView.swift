import SwiftUI

/// Renders one transcript row. Commentary is deliberately quiet so the final reply stands out.
struct ItemView: View {
    let item: DisplayItem
    /// True for the row the agent is working on right now.
    var isActive = false
    var onApproval: (UUID, DisplayItem.ApprovalState) -> Void = { _, _ in }

    var body: some View {
        switch item.kind {
        case .user: userBubble
        case .assistant: assistantText
        case .thought: ThoughtView(text: item.text, isActive: isActive)
        case .tool: toolRow
        case .plan: PlanCard(steps: item.planSteps)
        case .notice: noticeRow
        case .approval: ApprovalCard(item: item) { onApproval(item.id, $0) }
        }
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if item.steered {
                Label("Sent while working", systemImage: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let attachments = item.attachments, !attachments.isEmpty {
                SentAttachments(attachments: attachments)
            }
            if !item.text.isEmpty {
                Text(item.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.14)))
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
                Text(MarkdownText.inline(item.text))
                    .font(.callout)
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
        .font(.callout)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(item.text, systemImage: "hand.raised")
                .font(.callout.weight(.medium))
            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
            }
            switch item.approvalState ?? .expired {
            case .pending:
                HStack {
                    Button("Allow") { decide(.approved) }
                        .keyboardShortcut(.defaultAction)
                    Button("Allow for This Chat") { decide(.approvedForSession) }
                    Button("Deny", role: .destructive) { decide(.denied) }
                }
                .controlSize(.small)
            case .approved:
                outcome("Allowed", "checkmark.circle", .green)
            case .approvedForSession:
                outcome("Allowed for this chat", "checkmark.circle", .green)
            case .denied:
                outcome("Denied", "xmark.circle", .orange)
            case .expired:
                outcome("No longer needed", "clock", .secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: 520, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(item.approvalState == .pending ? 0.6 : 0.2)))
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
                .symbolEffect(.pulse, options: .repeating, isActive: isActive)
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
        case "in_progress": Image(systemName: "circle.dotted.circle").foregroundStyle(.tint)
        default: Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }
}

/// Attachments on a sent message: images as previews, other files as chips. Click to open.
private struct SentAttachments: View {
    let attachments: [Attachment]

    var body: some View {
        let images = attachments.filter { $0.kind == .image }
        let files = attachments.filter { $0.kind != .image }
        VStack(alignment: .trailing, spacing: 6) {
            if !images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(images) { image in
                        Button { NSWorkspace.shared.open(image.url) } label: {
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
/// Stays still when Reduce Motion is on.
private struct Shimmer: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay {
                TimelineView(.animation) { context in
                    let period = 1.8
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                    GeometryReader { geo in
                        let band = max(geo.size.width * 0.35, 60)
                        LinearGradient(colors: [.clear, .primary.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + (geo.size.width + band * 2) * t)
                    }
                    .mask(content)
                    .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

extension View {
    func shimmering(_ active: Bool) -> some View { modifier(Shimmer(active: active)) }
}
