import PhotosUI
import SwiftUI

/// An image waiting to go with the next message: a sketch, or a photo from the library.
struct PendingImage: Identifiable {
    let id = UUID()
    var preview: UIImage
    var upload: Companion.Upload
}

/// One chat: its transcript, kept current while it's open, and a message box.
struct ChatDetailView: View {
    let chat: Companion.ChatSummary
    /// Opens another chat (a fork) in this one's place.
    var open: (Companion.ChatSummary) -> Void = { _ in }
    @Environment(MobileStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var detail: Companion.ChatDetail?
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var composing: Bool
    /// The sketch canvas, when open.
    @State private var sketch: SketchRequest?
    @State private var pendingImages: [PendingImage] = []
    @State private var photoPicks: [PhotosPickerItem] = []
    @State private var showingSettings = false
    @State private var renaming = false
    @State private var newTitle = ""

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
                            ItemRow(item: item, chat: chat.id, actions: actions).id(item.id)
                        }
                        if summary.isRunning {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Working\u{2026}").font(.callout).foregroundStyle(.secondary)
                            }
                            .id("working")
                        }
                    } else if error == nil {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
                // A readable width on iPad, centered.
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: detail?.revision) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .fullScreenCover(item: $sketch) { request in
            SketchView(request: request) { image in
                if let data = image.pngData() {
                    pendingImages.append(PendingImage(preview: image, upload: .init(name: "Sketch.png", data: data)))
                }
            }
        }
        .onChange(of: photoPicks) { _, picks in
            guard !picks.isEmpty else { return }
            Task { await addPhotos(picks) }
        }
        .navigationTitle(summary.project ?? summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let settings = detail?.settings {
                ToolbarItem(placement: .principal) {
                    // Tap the title for the model, effort, and mode.
                    Button { showingSettings = true } label: {
                        VStack(spacing: 0) {
                            Text(summary.project ?? summary.title).font(.headline).lineLimit(1).foregroundStyle(.primary)
                            HStack(spacing: 3) {
                                Text(settings).lineLimit(1)
                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(detail?.options == nil)
                }
            }
            ToolbarItem(placement: .topBarTrailing) { chatMenu }
        }
        .sheet(isPresented: $showingSettings) {
            if let options = detail?.options {
                ChatSettingsSheet(options: options) { change in perform { try await store.change(change, in: chat.id) } }
                    .presentationDetents([.medium, .large])
            }
        }
        .alert("Rename Chat", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Rename") {
                let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { perform { try await store.rename(chat.id, to: title) } }
            }
            Button("Cancel", role: .cancel) {}
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

    private var chatMenu: some View {
        Menu {
            Button { showingSettings = true } label: { Label("Chat Settings", systemImage: "slider.horizontal.3") }
                .disabled(detail?.options == nil)
            Button { newTitle = summary.title; renaming = true } label: { Label("Rename", systemImage: "pencil") }
            if detail?.canFork == true {
                Button { forkChat() } label: { Label("Fork", systemImage: "arrow.triangle.branch") }
            }
            Divider()
            if detail?.isArchived == true {
                Button { perform { try await store.setArchived(false, chat: chat.id) } } label: {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button(role: .destructive) { perform { try await store.setArchived(true, chat: chat.id) } } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func forkChat() {
        Task {
            do {
                open(try await store.fork(chat.id).summary)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Actions

    private var actions: ItemActions {
        ItemActions(
            decide: { item, decision in perform { try await store.decide(decision, item: item, in: chat.id) } },
            answer: { item, answers in perform { try await store.answer(answers, item: item, in: chat.id) } },
            sendQueuedNow: { item in perform { try await store.sendQueuedNow(item, in: chat.id) } },
            markUp: { image in sketch = SketchRequest(background: image) }
        )
    }

    /// Runs a call to the Mac and shows the chat as it comes back.
    private func perform(_ call: @escaping () async throws -> Companion.ChatDetail) {
        Task {
            do {
                detail = try await call()
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func refresh() async {
        do {
            switch try await store.detail(chat.id, since: detail?.revision) {
            case .unchanged: break
            case .detail(let fresh):
                detail = fresh
                #if DEBUG
                // Simulator tests: open Chat Settings.
                if ProcessInfo.processInfo.environment["CHATTERBOX_TEST_SETTINGS"] != nil, !showingSettings, fresh.options != nil {
                    showingSettings = true
                }
                #endif
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var canSend: Bool {
        !sending && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty)
    }

    /// `now`: stop the agent and send this right away, instead of adding it to the reply.
    private func send(now: Bool = false) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingImages.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            detail = try await store.send(text, images: pendingImages.map(\.upload), now: now, to: chat.id)
            draft = ""
            pendingImages = []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Photos from the library, as JPEGs no bigger than the agents use.
    private func addPhotos(_ picks: [PhotosPickerItem]) async {
        for pick in picks {
            guard let data = try? await pick.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
            let scaled = image.scaledDown(toEdge: 2576)
            guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { continue }
            pendingImages.append(PendingImage(preview: scaled, upload: .init(name: "Photo.jpg", data: jpeg)))
        }
        photoPicks = []
    }

    // MARK: - Message box

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let detail, detail.turnStartedAt != nil || !(detail.backgroundTasks ?? []).isEmpty || detail.contextFraction != nil {
                ChatStatusBar(detail: detail).padding(.horizontal, 4)
            }
            if !pendingImages.isEmpty { pendingTray }
            composerRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 784)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// Images waiting to be sent; tap × to drop one.
    private var pendingTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImages) { pending in
                    Image(uiImage: pending.preview)
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            Button { pendingImages.removeAll { $0.id == pending.id } } label: {
                                Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .padding(3)
                        }
                }
            }
        }
    }

    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button { sketch = SketchRequest(background: nil) } label: { Label("Sketch", systemImage: "pencil.tip.crop.circle") }
                PhotosPicker(selection: $photoPicks, maxSelectionCount: 6, matching: .images) {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                }
            } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 30))
            } primaryAction: {
                sketch = SketchRequest(background: nil)
            }
            .tint(.secondary)
            .accessibilityLabel("Add a sketch or photo")

            TextField(summary.isRunning ? "Add something while it works\u{2026}" : "Message", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($composing)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(uiColor: .secondarySystemBackground)))

            if summary.isRunning {
                Button { perform { try await store.stop(chat.id) } } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 34)).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Stop")
            }

            // While the agent works, the send button adds to the reply; hold it to Send Now.
            Button { Task { await send() } } label: {
                Image(systemName: sending ? "ellipsis.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 34))
            }
            .disabled(!canSend)
            .contextMenu {
                if summary.isRunning {
                    Button { Task { await send(now: true) } } label: {
                        Label("Send Now (stop and send)", systemImage: "bolt.fill")
                    }
                    .disabled(!canSend)
                }
            }
            .accessibilityLabel("Send")
        }
    }
}

private extension UIImage {
    func scaledDown(toEdge maxEdge: CGFloat) -> UIImage {
        let edge = max(size.width, size.height)
        guard edge > maxEdge else { return self }
        let ratio = maxEdge / edge
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

/// One row of the transcript, styled like the Mac's.
private struct ItemRow: View {
    let item: Companion.Item
    let chat: UUID
    let actions: ItemActions

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
                    HStack(spacing: 8) {
                        Text("Queued").font(.caption2).foregroundStyle(.secondary)
                        Button("Send Now") { actions.sendQueuedNow(item.id) }
                            .font(.caption2.weight(.semibold))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)

        case .assistant:
            if item.isCommentary {
                MarkdownText(text: item.text).font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    MarkdownText(text: item.text)
                    if let seconds = item.workedSeconds {
                        Label("Worked for \(durationText(seconds))", systemImage: "clock")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }

        case .thought:
            if !item.text.isEmpty { ThoughtRow(text: item.text) }

        case .tool:
            ToolRow(item: item)

        case .plan:
            if let steps = item.planSteps, !steps.isEmpty { PlanCard(steps: steps) }

        case .shell:
            ShellRow(item: item)

        case .image:
            VStack(alignment: .leading, spacing: 6) {
                images
                ForEach(item.attachments.filter(RemotePreview.isPreviewable)) { file in
                    RemotePreview(file: file, chat: chat)
                }
                if !item.text.isEmpty { Text(item.text).font(.caption).foregroundStyle(.secondary) }
            }

        case .approval:
            if let approval = item.approval {
                ApprovalCard(item: item, approval: approval) { actions.decide(item.id, $0) }
            }

        case .questions:
            if let questions = item.questions, !questions.isEmpty {
                QuestionsCard(item: item, questions: questions) { actions.answer(item.id, $0) }
            }

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
            RemoteImage(file: file, chat: chat, onMarkUp: actions.markUp)
        }
    }
}

/// An image from the chat, fetched from the Mac. Hold it to mark it up or copy it.
private struct RemoteImage: View {
    let file: Companion.File
    let chat: UUID
    let onMarkUp: (UIImage) -> Void
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
        .contextMenu {
            if let image {
                Button { onMarkUp(image) } label: { Label("Mark Up", systemImage: "pencil.tip.crop.circle") }
                Button { UIPasteboard.general.image = image } label: { Label("Copy", systemImage: "doc.on.doc") }
            }
        }
        .task {
            if image == nil, let data = try? await store.file(file, in: chat) { image = UIImage(data: data) }
        }
    }
}
