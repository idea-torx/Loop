import SwiftUI

enum CoachTheme {
    static let mint = Color(red: 0.45, green: 1.0, blue: 0.78)
    static let blue = Color(red: 0.38, green: 0.66, blue: 1.0)
    static let ink = Color(red: 0.04, green: 0.05, blue: 0.07)
    static let panel = Color.white.opacity(0.08)
    static let panelStroke = Color.white.opacity(0.14)
    static let mutedText = Color.white.opacity(0.64)

    static var background: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.03, blue: 0.05),
                Color(red: 0.03, green: 0.07, blue: 0.09),
                Color(red: 0.01, green: 0.02, blue: 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct GlassPanel: ViewModifier {
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(CoachTheme.panelStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }
}

extension View {
    func glassPanel(radius: CGFloat = 22) -> some View {
        modifier(GlassPanel(radius: radius))
    }
}
