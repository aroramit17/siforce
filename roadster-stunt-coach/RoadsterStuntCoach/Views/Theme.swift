import SwiftUI

extension Color {
    static let roadsterRed = Color(red: 0.89, green: 0.09, blue: 0.14)
    static let asphalt = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let tarmac = Color(red: 0.13, green: 0.13, blue: 0.15)
    static let claimPaper = Color(red: 0.96, green: 0.94, blue: 0.88)
    static let claimInk = Color(red: 0.13, green: 0.14, blue: 0.2)
    static let stampGreen = Color(red: 0.1, green: 0.55, blue: 0.3)
    static let stampAmber = Color(red: 0.8, green: 0.5, blue: 0.05)
}

extension Font {
    /// Heavy italic display type, like a stunt-show poster.
    static func poster(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default).italic()
    }

    /// Typewriter type for the claim forms.
    static func form(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension LandingGrade {
    var color: Color {
        switch self {
        case .greased: return .green
        case .clean: return .white
        case .sketchy: return .orange
        }
    }
}

extension ClaimStatus {
    var color: Color {
        switch self {
        case .approved: return .stampGreen
        case .denied: return .roadsterRed
        case .underReview: return .stampAmber
        }
    }
}

struct DifficultyDots: View {
    let level: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { index in
                Circle()
                    .fill(index <= level ? Color.roadsterRed : Color.white.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Difficulty \(level) of 5")
    }
}

struct BigButtonStyle: ButtonStyle {
    var fill: Color = .roadsterRed

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.poster(22))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
