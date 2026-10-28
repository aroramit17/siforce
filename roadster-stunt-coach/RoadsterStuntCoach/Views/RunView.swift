import SwiftUI

struct RunView: View {
    @EnvironmentObject private var game: GameController

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    game.abandonRun()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(10)
                        .background(Color.tarmac, in: Circle())
                }
                .accessibilityLabel("Abandon run")
                Spacer()
                Text("CLAIMS \(Money.format(game.totalClaimed))")
                    .font(.form(15, weight: .bold))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white)

            FuelGaugeView(remaining: game.fuelRemaining)

            Spacer(minLength: 0)

            if case .countdown(let count) = game.phase {
                countdown(count)
            } else {
                stage
            }

            Spacer(minLength: 0)

            Text(game.coachLine)
                .font(.poster(22))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity)
                .id(game.coachLine)
                .transition(.opacity)

            if !game.motionAvailable && game.phase == .running {
                SimulatorStuntPad()
            }
        }
        .padding(20)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: game.claims.count)
    }

    private func countdown(_ count: Int) -> some View {
        VStack(spacing: 12) {
            Text("\(count)")
                .font(.poster(160))
                .foregroundStyle(Color.roadsterRed)
                .id(count)
                .transition(.scale(scale: 1.6).combined(with: .opacity))
            Text("Fuel ignites in \(count)…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: count)
    }

    @ViewBuilder
    private var stage: some View {
        if let claim = game.latestClaim {
            VStack(spacing: 14) {
                Text(claim.stunt.kind.title.uppercased())
                    .font(.poster(40))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Text(claim.stunt.landing.title.uppercased())
                        .foregroundStyle(claim.stunt.landing.color)
                    if claim.chain > 1 {
                        Text("CHAIN ×\(claim.chain) · \(String(format: "%.2f", claim.multiplier))×")
                            .foregroundStyle(Color.roadsterRed)
                    }
                }
                .font(.form(15, weight: .heavy))
                Text("CLAIM FILED \(Money.format(claim.amount))")
                    .font(.form(17, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.claimPaper, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Color.claimInk)
                    .rotationEffect(.degrees(-2))
                Text("\(game.claims.count) claim\(game.claims.count == 1 ? "" : "s") this run")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .id(claim.id)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.roadsterRed)
                    .symbolEffect(.pulse)
                Text("Pull a stunt!")
                    .font(.poster(32))
                Text("Ramp it, flip it, spin it. The meter is running.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// The Simulator has no gyro, so it gets buttons.
struct SimulatorStuntPad: View {
    @EnvironmentObject private var game: GameController

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO GYRO DETECTED · TAP TO FAKE IT")
                .font(.caption2.weight(.heavy))
                .tracking(1)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(StuntKind.allCases) { kind in
                    Button {
                        game.fakeStunt(kind)
                    } label: {
                        Text(kind.title.replacingOccurrences(of: "The ", with: ""))
                            .font(.footnote.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.tarmac, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
