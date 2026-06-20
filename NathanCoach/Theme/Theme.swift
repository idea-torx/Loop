import SwiftUI

// MARK: - Design tokens

enum CoachTheme {
    // Orange monochrome ramp (hue ~22–30°)
    static let ember = Color(red: 1.00, green: 0.42, blue: 0.10)   // primary accent  #FF6A1A
    static let flame = Color(red: 1.00, green: 0.56, blue: 0.26)   // bright highlight
    static let rust  = Color(red: 0.72, green: 0.26, blue: 0.06)   // deep shade
    static let glow  = Color(red: 1.00, green: 0.42, blue: 0.10).opacity(0.16) // soft fill tint

    // Single accent entry point
    static let accent = ember

    // Warm near-black base
    static let ink = Color(red: 0.05, green: 0.035, blue: 0.025)

    // MARK: Token groups (replace inline magic numbers)

    enum Fill {
        static let subtle = Color.white.opacity(0.045)
        static let soft   = Color.white.opacity(0.07)
        static let medium = Color.white.opacity(0.12)
    }

    enum Stroke {
        static let hairline = Color.white.opacity(0.08)
        static let panel    = Color.white.opacity(0.14)
        static let bright   = Color.white.opacity(0.32)
    }

    enum Radius {
        static let sm: CGFloat = 14
        static let md: CGFloat = 18
        static let lg: CGFloat = 22
        static let xl: CGFloat = 28
    }

    enum Space {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 10
        static let md: CGFloat = 12
        static let lg: CGFloat = 14
        static let xl: CGFloat = 18
    }

    enum Text {
        static let primary = Color.white
        static let muted   = Color.white.opacity(0.64)
        static let faint   = Color.white.opacity(0.4)
    }

    // MARK: Backward-compat aliases (so un-migrated screens read orange & compile)

    static let mint = accent              // was bright cyan
    static let blue = rust                // user chat bubbles / avatar → deep orange
    static let panel = Fill.soft
    static let panelStroke = Stroke.panel
    static let mutedText = Text.muted

    /// Static gradient fallback (used under Reduce Motion and as a base layer).
    static var background: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.04, blue: 0.025),
                Color(red: 0.10, green: 0.05, blue: 0.02),
                Color(red: 0.03, green: 0.02, blue: 0.015)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Animated moving-gradient background

/// Slow-drifting orange aurora over a warm near-black base.
/// Falls back to a static gradient when Reduce Motion is on.
struct AnimatedAuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CoachTheme.background

            if reduceMotion {
                staticBlobs
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    blobs(time: t)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var staticBlobs: some View {
        blobs(time: 0)
    }

    private func blobs(time: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                auroraBlob(
                    color: CoachTheme.ember,
                    size: w * 1.05,
                    x: w * (0.30 + 0.12 * sin(time * 0.11)),
                    y: h * (0.24 + 0.08 * cos(time * 0.09)),
                    opacity: 0.42
                )
                auroraBlob(
                    color: CoachTheme.rust,
                    size: w * 1.2,
                    x: w * (0.78 + 0.10 * cos(time * 0.08)),
                    y: h * (0.66 + 0.10 * sin(time * 0.07)),
                    opacity: 0.5
                )
                auroraBlob(
                    color: CoachTheme.flame,
                    size: w * 0.8,
                    x: w * (0.5 + 0.18 * sin(time * 0.06 + 1.5)),
                    y: h * (0.9 + 0.06 * cos(time * 0.1)),
                    opacity: 0.3
                )
            }
            .blur(radius: 60)
        }
    }

    private func auroraBlob(color: Color, size: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .position(x: x, y: y)
    }
}

// MARK: - Liquid Glass components

/// Liquid Glass panel (replaces the old ultraThinMaterial card).
struct GlassPanel: ViewModifier {
    var radius: CGFloat = CoachTheme.Radius.lg

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(CoachTheme.Stroke.panel, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }
}

extension View {
    /// Backward-compatible name kept so existing call sites work; now Liquid Glass.
    func glassPanel(radius: CGFloat = CoachTheme.Radius.lg) -> some View {
        modifier(GlassPanel(radius: radius))
    }

    func liquidGlassPanel(radius: CGFloat = CoachTheme.Radius.lg) -> some View {
        modifier(GlassPanel(radius: radius))
    }
}

/// Press-to-scale feedback for interactive glass.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// Titled glass container used across screens.
struct GlassCard<Content: View>: View {
    var radius: CGFloat = CoachTheme.Radius.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .glassPanel(radius: radius)
    }
}

/// Capsule pill with glass + optional accent tint.
struct GlassPillButton: View {
    let title: String
    var systemImage: String? = nil
    var isProminent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isProminent ? Color.black : CoachTheme.Text.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(
                isProminent ? .regular.tint(CoachTheme.accent).interactive() : .regular.interactive(),
                in: Capsule()
            )
            .overlay { Capsule().stroke(CoachTheme.Stroke.hairline, lineWidth: 1) }
        }
        .buttonStyle(.pressable)
    }
}

/// Primary circular/rounded accent action (send, log, etc.).
struct AccentButton: View {
    let systemImage: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 46, height: 46)
                .glassEffect(.regular.tint(CoachTheme.accent).interactive(), in: Circle())
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
    }
}

/// Metric tile (Trends grid + Today health card).
struct MetricTile: View {
    let title: String
    let value: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(CoachTheme.Text.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(CoachTheme.Text.muted)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(CoachTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared selectable chip (task rows, day strip).
struct SelectableChip<Content: View>: View {
    var isSelected: Bool
    var radius: CGFloat = CoachTheme.Radius.sm
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isSelected ? CoachTheme.glow : CoachTheme.Fill.soft)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(isSelected ? CoachTheme.accent.opacity(0.6) : CoachTheme.Stroke.hairline, lineWidth: 1)
            }
            .animation(.snappy(duration: 0.25), value: isSelected)
    }
}

// MARK: - Hero / data components

/// Apple-Fitness-style circular progress ring with an animated gradient stroke.
struct ProgressRing: View {
    var progress: Double            // 0...1
    var lineWidth: CGFloat = 14
    var size: CGFloat = 150

    var body: some View {
        ZStack {
            Circle()
                .stroke(CoachTheme.Fill.medium, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(
                        colors: [CoachTheme.rust, CoachTheme.ember, CoachTheme.flame, CoachTheme.ember],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: CoachTheme.ember.opacity(0.5), radius: 8)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.9, dampingFraction: 0.75), value: progress)
    }
}

/// Big-numeral hero/stat readout (Strava-style).
struct HeroStat: View {
    let value: String
    let label: String
    var systemImage: String? = nil
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(CoachTheme.accent)
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(CoachTheme.Text.primary)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(CoachTheme.Text.faint)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}

/// Animated circular checkbox.
struct CircularCheck: View {
    var isOn: Bool
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .stroke(isOn ? CoachTheme.accent : CoachTheme.Text.faint, lineWidth: 2)
                .frame(width: size, height: size)
            Circle()
                .fill(CoachTheme.accent)
                .frame(width: size, height: size)
                .scaleEffect(isOn ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.black)
                .scaleEffect(isOn ? 1 : 0)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isOn)
    }
}

/// Rounded leading icon tile used by list rows.
struct IconTile: View {
    let systemImage: String
    var tint: Color = CoachTheme.accent
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.28), tint.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.35), lineWidth: 1)
            }
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(tint)
            }
    }
}

/// Section header with optional trailing accessory.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(CoachTheme.Text.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(CoachTheme.Text.muted)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Haptics

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
