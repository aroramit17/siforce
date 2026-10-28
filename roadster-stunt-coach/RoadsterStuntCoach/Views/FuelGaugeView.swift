import SwiftUI

struct FuelGaugeView: View {
    let remaining: TimeInterval

    private var fraction: Double { max(0, min(1, remaining / FuelGauge.capacity)) }

    private var color: Color {
        if fraction > 0.5 { return .green }
        if fraction > 0.25 { return .yellow }
        return .roadsterRed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("FUEL", systemImage: "fuelpump.fill")
                    .font(.caption.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2fs", remaining))
                    .font(.form(28, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: geo.size.width * fraction)
                    // One notch per second of fuel.
                    HStack(spacing: 0) {
                        ForEach(1..<Int(FuelGauge.capacity), id: \.self) { _ in
                            Spacer()
                            Rectangle().fill(Color.black.opacity(0.35)).frame(width: 2)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 22)
            .clipShape(Capsule())

            HStack {
                Text("E")
                Spacer()
                Text("F")
            }
            .font(.form(11, weight: .bold))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fuel")
        .accessibilityValue(String(format: "%.1f seconds left", remaining))
    }
}
