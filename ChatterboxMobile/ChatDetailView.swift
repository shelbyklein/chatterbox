import SwiftUI

/// One chat: its transcript, kept current while it's open, and a message box.
struct ChatDetailView: View {
    let chat: Companion.ChatSummary
    @Environment(MobileStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var detail: Companion.ChatDetail?
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var composing: Bool

    private var summary: Companion.ChatSummary { detail?.summary ?? chat }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let detail {
                        if detail.earlierCount > 0 {
                            Text("\(detail.earlierCount) earlier messages are on the Mac.")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(detail.items) { item in
                            ItemRow(item: item, chat: chat.id).id(item.id)
                        }
                        if summary.isRunning {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Working\u{2026}").font(.callout).foregroundStyle(.secondary)
                            }
                            .id("working")
                        }
                    } else if let error {
                        Text(error).foregroundStyle(.orange)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: detail?.revision) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(summary.project ?? summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let settings = detail?.settings {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(summary.project ?? summary.title).font(.headline).lineLimit(1)
                        Text(settings).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        // Checks for changes often while the agent works, less when it's idle.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(summary.isRunning ? 1.2 : 4))
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(summary.isRunning ? "Add something while it works\u{2026}" : "Message", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($composing)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(uiColor: .secondarySystemBackground)))
            Button {
                Task { await send() }
            } label: {
                Image(systemName: sending ? "ellipsis.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 34))
            }
            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func refresh() async {
        do {
            switch try await store.detail(chat.id, since: detail?.revision) {
            case .unchanged: break
            case .detail(let fresh): detail = fresh
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            detail = try await store.send(text, to: chat.id)
            draft = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One row of the transcript, styled like the Mac's.
private struct ItemRow: View {
    let item: Companion.Item
    let chat: UUID

    var body: some View {
        switch item.kind {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if !item.text.isEmpty {
                    Text(item.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color.accentColor.opacity(0.22)))
                }
                images
                if item.isQueued {
                    Text("Queued").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)

        case .assistant:
            if item.isCommentary {
                MarkdownText(text: item.text).font(.callout).foregroundStyle(.secondary)
            } else {
                MarkdownText(text: item.text)
            }

        case .thought:
            EmptyView()

        case .tool:
            Label {
                Text(item.text).lineLimit(2)
            } icon: {
                Image(systemName: item.toolState == "failed" ? "xmark.circle" : item.toolState == "running" ? "circle.dotted" : "checkmark.circle")
                    .foregroundStyle(item.toolState == "failed" ? .red : item.toolState == "running" ? .secondary : .green)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

        case .plan:
            Text(item.text).font(.footnote.monospaced()).foregroundStyle(.secondary)

        case .shell:
            Text("$ " + item.text).font(.footnote.monospaced()).foregroundStyle(.secondary)

        case .image:
            VStack(alignment: .leading, spacing: 6) {
                images
                if !item.text.isEmpty { Text(item.text).font(.caption).foregroundStyle(.secondary) }
            }

        case .approval, .questions:
            VStack(alignment: .leading, spacing: 6) {
                Label(item.isPending ? "Waiting for you on the Mac" : (item.kind == .approval ? "Approval" : "Questions"),
                      systemImage: item.isPending ? "hand.raised.fill" : "checkmark.seal")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(item.isPending ? .yellow : .secondary)
                Text(item.text).font(.callout).foregroundStyle(.secondary).lineLimit(8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(item.isPending ? 0.12 : 0.04)))

        case .notice:
            Text(item.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var images: some View {
        ForEach(item.attachments.filter(\.isImage)) { file in
            RemoteImage(file: file, chat: chat)
        }
    }
}

/// An image from the chat, fetched from the Mac.
private struct RemoteImage: View {
    let file: Companion.File
    let chat: UUID
    @Environment(MobileStore.self) private var store
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemBackground))
                    .frame(height: 160)
                    .overlay(ProgressView())
            }
        }
        .frame(maxWidth: 320)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            if image == nil, let data = try? await store.file(file, in: chat) { image = UIImage(data: data) }
        }
    }
}
