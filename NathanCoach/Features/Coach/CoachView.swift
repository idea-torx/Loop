import SwiftUI

struct CoachView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ""
    @State private var isResponding = false
    @State private var showsDrawer = false
    @FocusState private var isFocused: Bool

    private let quickPrompts: [(label: String, prefill: String, icon: String)] = [
        ("Weigh-in", "I weighed in at ", "scalemass.fill"),
        ("Log lunch", "Lunch was ", "fork.knife"),
        ("Earlier nudge", "Move my gym nudge earlier", "clock.arrow.circlepath"),
        ("Review today", "Review today so far", "sparkles")
    ]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(appState.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            if isResponding {
                                HStack(spacing: 10) {
                                    coachOrb(size: 30)
                                    TypingIndicator()
                                    Spacer(minLength: 54)
                                }
                                .id("typing")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: appState.messages.count) { _, _ in scrollToEnd(proxy) }
                    .onChange(of: isResponding) { _, _ in scrollToEnd(proxy) }
                    .onChange(of: appState.activeConversationID) { _, _ in scrollToEnd(proxy) }
                }

                quickPromptRow
                composer
                    .padding(.horizontal, 14)
                    .padding(.bottom, 96)
            }
            .background(CoachTheme.background)

            ConversationDrawer(isOpen: $showsDrawer)
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) {
            if isResponding {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = appState.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: Compact top bar

    private var topBar: some View {
        ZStack {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text(appState.activeConversation?.title ?? "Coach")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
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
                .foregroundStyle(CoachTheme.accent)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.interactive(), in: Circle())
                .overlay { Circle().stroke(CoachTheme.Stroke.hairline, lineWidth: 1) }
        }
        .buttonStyle(.pressable)
    }

    private func coachOrb(size: CGFloat) -> some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = 1 + 0.04 * sin(t * 2)
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [CoachTheme.rust, CoachTheme.ember, CoachTheme.flame, CoachTheme.rust],
                            center: .center
                        )
                    )
                    .scaleEffect(pulse)
                    .shadow(color: CoachTheme.ember.opacity(0.5), radius: size * 0.22, y: 4)
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.85))
            }
            .frame(width: size, height: size)
        }
    }

    // MARK: Quick prompts

    private var quickPromptRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(quickPrompts, id: \.label) { prompt in
                    GlassPillButton(title: prompt.label, systemImage: prompt.icon) {
                        Haptics.soft()
                        draft = prompt.prefill
                        isFocused = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message your coach…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .glassEffect(.regular, in: Capsule())
                .overlay {
                    Capsule().stroke(CoachTheme.accent.opacity(isFocused ? 0.5 : 0.12), lineWidth: 1)
                }

            AccentButton(systemImage: "arrow.up", isEnabled: !trimmedDraft.isEmpty) {
                send()
            }
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        let message = trimmedDraft
        guard !message.isEmpty else { return }
        draft = ""
        Haptics.light()
        isResponding = true
        Task {
            await appState.sendCoachMessage(message)
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
                        .glassEffect(.regular.interactive(), in: Circle())
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
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [CoachTheme.flame, CoachTheme.ember],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                )
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
    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isUser {
                Spacer(minLength: 48)
            } else {
                assistantAvatar
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                Text(message.text)
                    .font(.body)
                    .lineSpacing(2)
                    .foregroundStyle(isUser ? .black : CoachTheme.Text.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        if isUser {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [CoachTheme.flame, CoachTheme.ember],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(CoachTheme.Fill.soft)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
                                }
                        }
                    }

                Text(message.createdAt.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(CoachTheme.Text.faint)
                    .padding(.horizontal, 4)
            }

            if isUser {
                userAvatar
            } else {
                Spacer(minLength: 48)
            }
        }
        .transition(.move(edge: isUser ? .trailing : .leading).combined(with: .opacity))
    }

    private var assistantAvatar: some View {
        ZStack {
            Circle().fill(CoachTheme.glow)
            Image(systemName: "sparkle")
                .font(.caption.weight(.bold))
                .foregroundStyle(CoachTheme.accent)
        }
        .frame(width: 30, height: 30)
    }

    private var userAvatar: some View {
        Text("L")
            .font(.caption.weight(.bold))
            .foregroundStyle(.black)
            .frame(width: 30, height: 30)
            .background(CoachTheme.ember, in: Circle())
    }
}
