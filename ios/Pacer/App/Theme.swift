import SwiftUI

/// Pacer visual language: a dark, high-contrast, glanceable running UI.
/// Not a SaaS dashboard — big numerals, few words, strong accents.
enum Theme {
    static let background = Color(red: 0.04, green: 0.05, blue: 0.09)
    static let surface = Color(red: 0.09, green: 0.10, blue: 0.16)
    static let surfaceRaised = Color(red: 0.13, green: 0.14, blue: 0.22)
    static let accent = Color(red: 0.36, green: 0.95, blue: 0.66) // pace green
    static let accentAlt = Color(red: 0.42, green: 0.62, blue: 1.0) // music blue
    static let warn = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.38)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.07, blue: 0.13), background],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {
    func pacerCard() -> some View {
        self
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Monospaced-digit numeral style for stable, glanceable numbers.
struct StatNumeral: View {
    let value: String
    let unit: String
    var color: Color = Theme.textPrimary
    var size: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
