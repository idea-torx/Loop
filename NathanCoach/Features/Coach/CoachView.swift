import SwiftUI

struct CoachView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ""
    @State private var isResponding = false
    @FocusState private var isFocused: Bool

    private let quickPrompts: [(label: String, prefill: String, icon: String)] = [
        ("Weigh-in", "I weighed in at ", "scalemass.fill"),
        ("Log lunch", "Lunch was ", "fork.knife"),
        ("Earlier nudge", "Move my gym nudge earlier", "clock.arrow.circlepath"),
        ("Review today", "Review today so far", "sparkles")
    ]

    var body: some View {
        VStack(spacing: 0) {
            coachHeader
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
            }

            quickPromptRow
            composer
                .padding(.horizontal, 14)
                .padding(.bottom, 96)
        }
        .background(CoachTheme.background)
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

    // MARK: Header

    private var coachHeader: some View {
        HStack(spacing: 14) {
            coachOrb(size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text("Coach")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("Online · Claude Haiku")
                        .font(.caption)
                        .foregroundStyle(CoachTheme.Text.muted)
                }
            }
            Spacer()
        }
        .padding(14)
        .glassPanel(radius: CoachTheme.Radius.xl)
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
