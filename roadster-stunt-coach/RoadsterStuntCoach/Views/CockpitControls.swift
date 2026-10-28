import SwiftUI

/// A round analog gauge with a 270° sweep, a needle and a digital readout.
struct DialGauge: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let unit: String
    var format = "%.0f"
    var warning = false
    var diameter: CGFloat = 78

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        return max(0, min(1, (value - range.lowerBound) / span))
    }

    private var tint: Color { warning ? .roadsterRed : .gaugeCyan }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.55))
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(7)
            Circle()
                .trim(from: 0, to: 0.75 * fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(7)
            Capsule()
                .fill(Color.white)
                .frame(width: 2, height: diameter * 0.32)
                .offset(y: -diameter * 0.16)
                .rotationEffect(.degrees(-135 + 270 * fraction))
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
            VStack(spacing: 0) {
                Text(String(format: format, value))
                    .font(.form(14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(warning ? Color.roadsterRed : .white)
                Text(unit)
                    .font(.form(7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .offset(y: diameter * 0.2)
            Text(title)
                .font(.form(8, weight: .heavy))
                .tracking(1)
                .foregroundStyle(.secondary)
                .offset(y: -diameter * 0.2)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(String(format: format, value)) \(unit)")
    }
}

/// A thin horizontal meter, 0 to 1.
struct BarGauge: View {
    let title: String
    let fraction: Double
    var tint: Color = .gaugeCyan
    var trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer(minLength: 4)
                if let trailing { Text(trailing).monospacedDigit() }
            }
            .font(.form(8, weight: .heavy))
            .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * max(0, min(1, fraction)))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(max(0, min(1, fraction)) * 100)) percent")
    }
}

/// A caution light that glows when its condition is true.
struct Annunciator: View {
    let title: String
    let lit: Bool
    var color: Color = .roadsterRed

    var body: some View {
        Text(title)
            .font(.form(8, weight: .heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .foregroundStyle(lit ? Color.black : Color.white.opacity(0.25))
            .background(lit ? color : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(!lit)
    }
}

/// A big round button that stays "on" for as long as a finger is on it.
/// Several can be held at once (throttle with one thumb, boost with the other).
struct HoldButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    var diameter: CGFloat = 76
    var enabled = true
    @Binding var isPressed: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isPressed ? tint : tint.opacity(0.18))
                .shadow(color: isPressed ? tint.opacity(0.8) : .clear, radius: 12)
            Circle()
                .strokeBorder(tint.opacity(enabled ? 1 : 0.3), lineWidth: 3)
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: diameter * 0.26, weight: .bold))
                Text(title)
                    .font(.form(diameter * 0.12, weight: .heavy))
            }
            .foregroundStyle(isPressed ? Color.black : Color.white.opacity(enabled ? 1 : 0.35))
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isPressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isPressed.toggle() }
    }
}

/// The suction fan's guarded toggle, with a status light: off, spooling, sealed, or overheated.
struct FanSwitch: View {
    let isOn: Bool
    let rpm: Double
    let locked: Bool
    let action: () -> Void

    private var status: (String, Color) {
        if locked { return ("OVERHEAT", .roadsterRed) }
        if rpm > 0.9 { return ("SEALED", .fanTeal) }
        if rpm > 0.05 { return (isOn ? "SPOOLING" : "SPINNING DOWN", .yellow) }
        return ("OFF", Color.white.opacity(0.35))
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text("SUCTION FAN")
                    .font(.form(8, weight: .heavy))
                    .foregroundStyle(.secondary)
                ZStack(alignment: isOn ? .top : .bottom) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 34, height: 52)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? Color.fanTeal : Color(white: 0.4))
                        .frame(width: 28, height: 24)
                        .padding(3)
                }
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.yellow.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                HStack(spacing: 4) {
                    Circle().fill(status.1).frame(width: 7, height: 7)
                    Text(status.0)
                        .font(.form(8, weight: .bold))
                        .foregroundStyle(status.1)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .animation(.easeOut(duration: 0.12), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Suction fan")
        .accessibilityValue(status.0)
    }
}
