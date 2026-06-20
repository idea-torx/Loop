import SwiftUI

struct CoachView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private let quickPrompts = [
        "I weighed in at ",
        "Lunch was ",
        "Move my gym nudge earlier",
        "Review today so far"
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        coachHeader
                        quickPromptRow
                        messageTimeline
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 168)
                }
                .background(CoachTheme.background)
                .navigationTitle("Coach")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    composer
                        .padding(.horizontal, 14)
                        .padding(.bottom, 92)
                }
                .onChange(of: appState.messages.count) { _, _ in
                    if let last = appState.messages.last {
                        withAnimation(.snappy) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var coachHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [CoachTheme.mint, CoachTheme.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: CoachTheme.mint.opacity(0.22), radius: 14, y: 8)

                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.82))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Your day, in conversation")
                        .font(.title2.weight(.bold))
                    Text("Tell me what happened. I’ll update meals, nudges, workouts, and constraints without making you dig through forms.")
                        .font(.subheadline)
                        .foregroundStyle(CoachTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                contextTile(title: "Meal timing", value: appState.settings.mealTiming, icon: "clock")
                contextTile(title: "Gym rhythm", value: appState.settings.gymDays, icon: "calendar")
            }
        }
        .padding(18)
        .glassPanel(radius: 24)
    }

    private var quickPromptRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(quickPrompts, id: \.self) { prompt in
                    Button {
                        draft = prompt
                        isFocused = true
                    } label: {
                        Text(prompt)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.86))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(.thinMaterial, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var messageTimeline: some View {
        VStack(spacing: 14) {
            ForEach(appState.messages) { message in
                messageRow(message)
                    .id(message.id)
            }
        }
    }

    private func messageRow(_ message: CoachMessage) -> some View {
        let isUser = message.role == .user

        return HStack(alignment: .bottom, spacing: 10) {
            if !isUser {
                avatar
            } else {
                Spacer(minLength: 54)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                Text(message.text)
                    .font(.body)
                    .lineSpacing(2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .background {
                        if isUser {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(CoachTheme.blue.opacity(0.72))
                        } else {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                }
                        }
                    }

                Text(message.createdAt.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.38))
                    .padding(.horizontal, 4)
            }

            if isUser {
                userAvatar
            } else {
                Spacer(minLength: 54)
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message your coach...", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(isFocused ? 0.24 : 0.1), lineWidth: 1)
                }

            Button {
                let message = draft
                draft = ""
                Task { await appState.sendCoachMessage(message) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(CoachTheme.mint, in: Circle())
                    .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background(Color.white.opacity(0.012), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(CoachTheme.mint.opacity(0.16))
            Image(systemName: "sparkle")
                .font(.caption.weight(.bold))
                .foregroundStyle(CoachTheme.mint)
        }
        .frame(width: 30, height: 30)
    }

    private var userAvatar: some View {
        Text("L")
            .font(.caption.weight(.bold))
            .foregroundStyle(.black.opacity(0.82))
            .frame(width: 30, height: 30)
            .background(CoachTheme.blue, in: Circle())
    }

    private func contextTile(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
