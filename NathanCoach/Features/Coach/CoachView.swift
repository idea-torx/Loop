import PhotosUI
import SwiftUI
import UIKit

struct CoachView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ""
    @State private var isResponding = false
    @State private var showsDrawer = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var showsPhotoPicker = false
    @State private var revealTick = 0
    @State private var generationStartedAt: Date?
    @State private var revealedMessageIDs: Set<CoachMessage.ID> = []
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.075)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if appState.messages.isEmpty {
                                emptyOpenChatState
                            }
                            ForEach(appState.messages) { message in
                                MessageBubble(
                                    message: message,
                                    isAnimating: shouldReveal(message),
                                    onRevealTick: { revealTick += 1 },
                                    onRevealComplete: {
                                        revealedMessageIDs.insert(message.id)
                                        if generationStartedAt != nil {
                                            generationStartedAt = nil
                                        }
                                    }
                                )
                                    .id(message.id)
                            }
                            if isResponding {
                                HStack(spacing: 10) {
                                    TypingIndicator()
                                    Spacer(minLength: 48)
                                }
                                .id("typing")
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("chat-bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 18)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(TapGesture().onEnded { isFocused = false })
                    .onAppear {
                        markExistingMessagesRevealed()
                        scrollToEnd(proxy, animated: false)
                        scheduleBottomScroll(proxy, animated: false)
                    }
                    .onChange(of: appState.messages.count) { _, _ in scheduleBottomScroll(proxy) }
                    .onChange(of: isResponding) { _, _ in scheduleBottomScroll(proxy) }
                    .onChange(of: appState.activeConversationID) { _, _ in
                        markExistingMessagesRevealed()
                        scheduleBottomScroll(proxy, animated: false)
                    }
                    .onChange(of: revealTick) { _, _ in scrollToEnd(proxy) }
                    .onChange(of: isFocused) { _, focused in
                        guard focused else { return }
                        scheduleKeyboardBottomScroll(proxy)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                        scheduleKeyboardBottomScroll(proxy)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                        scrollToEnd(proxy, animated: false)
                    }
                }

                composer
                    .padding(.horizontal, 20)
                    .padding(.bottom, composerBottomPadding)
                    .animation(.snappy(duration: 0.22), value: isFocused)
            }
            .background(Color(red: 0.07, green: 0.07, blue: 0.075))
            .sheet(isPresented: $showsCamera) {
                CameraCaptureView { data in
                    sendMealImage(data)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showsPhotoPicker) {
                CoachPhotoPicker(photoItem: $photoItem)
                    .preferredColorScheme(.dark)
                    .presentationDetents([.height(180)])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    await MainActor.run { photoItem = nil }
                    await MainActor.run { sendMealImage(data) }
                }
            }

            ConversationDrawer(isOpen: $showsDrawer)
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let action = {
            if isResponding {
                proxy.scrollTo("typing", anchor: .bottom)
            } else {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }

        if animated {
            withAnimation(.snappy, action)
        } else {
            action()
        }
    }

    private func scheduleBottomScroll(_ proxy: ScrollViewProxy, animated: Bool = true) {
        scrollToEnd(proxy, animated: animated)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 70_000_000)
            scrollToEnd(proxy, animated: animated)
            try? await Task.sleep(nanoseconds: 180_000_000)
            scrollToEnd(proxy, animated: false)
        }
    }

    private func scheduleKeyboardBottomScroll(_ proxy: ScrollViewProxy) {
        scrollToEnd(proxy)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            scrollToEnd(proxy)
            try? await Task.sleep(nanoseconds: 260_000_000)
            scrollToEnd(proxy)
            try? await Task.sleep(nanoseconds: 420_000_000)
            scrollToEnd(proxy, animated: false)
        }
    }

    private func markExistingMessagesRevealed() {
        for message in appState.messages where message.role == .assistant {
            revealedMessageIDs.insert(message.id)
        }
    }

    private func shouldReveal(_ message: CoachMessage) -> Bool {
        guard message.role == .assistant,
              message.id == appState.messages.last?.id,
              !revealedMessageIDs.contains(message.id),
              let generationStartedAt else { return false }
        return message.createdAt >= generationStartedAt
    }

    private var emptyOpenChatState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask anything.")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(CoachTheme.Text.primary)
            Text("Training swaps, meal choices, soreness, motivation, plan tweaks, or a straight fitness question.")
                .font(.subheadline)
                .foregroundStyle(CoachTheme.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 36)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Compact top bar

    private var topBar: some View {
        ZStack {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text(appState.activeConversation?.title ?? "Coach")
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: 200)

            HStack {
                iconButton("square.and.pencil") {
                    Haptics.light()
                    isFocused = false
                    withAnimation(.snappy(duration: 0.3)) { appState.startNewConversation() }
                }
                .accessibilityLabel("New chat")

                Spacer()

                iconButton("bubble.left.and.bubble.right") {
                    Haptics.light()
                    isFocused = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showsDrawer = true }
                }
                .accessibilityLabel("All chats")
            }
        }
        .frame(height: 44)
    }

    private func iconButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CoachTheme.Text.muted)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.pressable)
    }

    // MARK: Composer

    private var composer: some View {
        HStack(alignment: .center, spacing: 10) {
            Menu {
                Button {
                    Haptics.light()
                    isFocused = false
                    showsCamera = true
                } label: {
                    Label("Camera", systemImage: "camera")
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                Button {
                    Haptics.light()
                    isFocused = false
                    showsPhotoPicker = true
                } label: {
                    Label("Photo Library", systemImage: "photo")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CoachTheme.Text.muted)
                    .frame(width: isFocused ? 34 : 30, height: isFocused ? 36 : 32)
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)

            TextField("Message your coach…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .lineLimit(1...5)
                .padding(.vertical, 12)
                .submitLabel(.send)
                .onSubmit(send)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(trimmedDraft.isEmpty ? CoachTheme.Text.faint : .black)
                    .frame(width: 32, height: 32)
                    .background(trimmedDraft.isEmpty ? Color.white.opacity(0.08) : CoachTheme.Text.primary, in: Circle())
            }
            .disabled(trimmedDraft.isEmpty)
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .frame(minHeight: isFocused ? 48 : 46)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: isFocused ? 18 : 999, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isFocused ? 18 : 999, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.18 : 0.08), lineWidth: 1)
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var composerBottomPadding: CGFloat {
        isFocused ? 8 : 72
    }

    private func send() {
        let message = trimmedDraft
        guard !message.isEmpty else { return }
        draft = ""
        Haptics.light()
        isResponding = true
        generationStartedAt = Date()
        Task {
            await appState.sendCoachMessage(message)
            isResponding = false
        }
    }

    private func sendMealImage(_ data: Data) {
        let note = trimmedDraft.isEmpty ? nil : trimmedDraft
        Haptics.light()
        isResponding = true
        generationStartedAt = Date()
        Task {
            await appState.sendMealImageToHaiku(imageData: data, note: note)
            draft = ""
            isResponding = false
        }
    }
}

// MARK: - Conversations drawer

private struct ConversationDrawer: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isOpen: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if isOpen {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { isOpen = false }

                panel
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isOpen)
    }

    private var sortedConversations: [Conversation] {
        appState.conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Chats")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                Button { isOpen = false } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(CoachTheme.Text.muted)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.pressable)
            }
            .padding(.top, 8)

            Button {
                Haptics.light()
                appState.startNewConversation()
                isOpen = false
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .semibold))
                    Text("New chat")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                }
                .foregroundStyle(CoachTheme.Text.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.pressable)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(sortedConversations) { convo in
                        conversationRow(convo)
                    }
                }
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(CoachTheme.ink.opacity(0.5))
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(CoachTheme.Stroke.hairline).frame(width: 1).ignoresSafeArea()
        }
    }

    private func conversationRow(_ convo: Conversation) -> some View {
        let isActive = convo.id == appState.activeConversationID

        return Button {
            Haptics.soft()
            appState.selectConversation(convo)
            isOpen = false
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(convo.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(CoachTheme.Text.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(convo.updatedAt.formatted(.relative(presentation: .numeric)))
                        .font(.caption2)
                        .foregroundStyle(CoachTheme.Text.faint)
                }
                Text(convo.preview)
                    .font(.caption)
                    .foregroundStyle(CoachTheme.Text.muted)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                    .fill(isActive ? CoachTheme.glow : CoachTheme.Fill.soft)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                    .stroke(isActive ? CoachTheme.accent.opacity(0.6) : CoachTheme.Stroke.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: CoachMessage
    let isAnimating: Bool
    var onRevealTick: () -> Void = {}
    var onRevealComplete: () -> Void = {}
    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if isUser {
                Spacer(minLength: 48)
            } else {
                Image("LoopMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .padding(5)
                    .background(Color.white.opacity(0.045), in: Circle())
                    .padding(.top, 4)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                RevealingMarkdownText(
                    source: message.text,
                    isAnimating: isAnimating && !isUser,
                    onRevealTick: onRevealTick,
                    onRevealComplete: onRevealComplete
                )
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isUser ? Color.white.opacity(0.085) : Color.white.opacity(0.045))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(isUser ? 0.075 : 0.055), lineWidth: 1)
                    }

                Text(message.createdAt.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.32))
                    .padding(.horizontal, isUser ? 4 : 0)
            }
            .frame(maxWidth: isUser ? 280 : 310, alignment: isUser ? .trailing : .leading)

            if isUser {
                EmptyView()
            } else {
                Spacer(minLength: 28)
            }
        }
        .transition(.opacity)
    }
}

private struct MarkdownText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        Text(rendered)
            .textSelection(.enabled)
    }

    private var rendered: AttributedString {
        if let attributed = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(source)
    }
}

private struct RevealingMarkdownText: View {
    let source: String
    let isAnimating: Bool
    var onRevealTick: () -> Void = {}
    var onRevealComplete: () -> Void = {}
    @State private var visibleText = ""
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        MarkdownText(displayText)
            .onAppear { startRevealIfNeeded() }
            .onChange(of: source) { _, _ in startRevealIfNeeded() }
            .onDisappear {
                revealTask?.cancel()
                revealTask = nil
            }
    }

    private var displayText: String {
        isAnimating ? visibleText : source
    }

    private func startRevealIfNeeded() {
        revealTask?.cancel()

        guard isAnimating else {
            visibleText = source
            return
        }

        visibleText = ""
        let chunks = source.revealChunks
        revealTask = Task {
            var buffer = ""
            for chunk in chunks {
                if Task.isCancelled { return }
                buffer += chunk
                await MainActor.run {
                    visibleText = buffer
                    onRevealTick()
                }

                let delay: UInt64 = chunk.hasSuffix(".")
                    || chunk.hasSuffix(",")
                    || chunk.hasSuffix(":")
                    || chunk.hasSuffix("\n") ? 46_000_000 : 18_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
            await MainActor.run {
                visibleText = source
                onRevealComplete()
            }
        }
    }
}

private struct CoachPhotoPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose a meal photo")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(CoachTheme.Text.primary)

            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack(spacing: 10) {
                    Image(systemName: "photo")
                    Text("Open Photo Library")
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(CoachTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)

            Button("Cancel") { dismiss() }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(CoachTheme.Text.muted)
        }
        .padding(20)
        .background(CoachTheme.background.ignoresSafeArea())
        .onChange(of: photoItem) { _, item in
            if item != nil {
                dismiss()
            }
        }
    }
}

private extension String {
    var revealChunks: [String] {
        var chunks: [String] = []
        var buffer = ""

        for character in self {
            buffer.append(character)
            if character.isWhitespace || [".", ",", ":", ";", "!", "?"].contains(String(character)) {
                chunks.append(buffer)
                buffer = ""
            }
        }

        if !buffer.isEmpty {
            chunks.append(buffer)
        }
        return chunks
    }
}

// MARK: - Camera capture

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (Data) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (Data) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.82) {
                onCapture(data)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
