import SwiftUI

struct TitleView: View {
    @EnvironmentObject private var game: GameController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                pitch
                StuntGuideView()
                safetyNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if game.bestTotal > 0 {
                    Text("Personal worst insurance record: \(Money.format(game.bestTotal))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Button("IGNITION") { game.startRun() }
                    .buttonStyle(BigButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ROADSTER")
                .font(.poster(52))
                .foregroundStyle(Color.roadsterRed)
            Text("STUNT COACH")
                .font(.poster(40))
                .foregroundStyle(.white)
            Text("Unofficial. Uninsured. Mildly airborne.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Hold your phone like a tiny car, screen facing you.", systemImage: "iphone")
            Label("You get 4 seconds of fuel. That's the whole launch window.", systemImage: "fuelpump.fill")
            Label("Every stunt files an insurance claim. Clean landings refund a little fuel.", systemImage: "doc.text.fill")
            Label("Land stunts back to back to chain a multiplier.", systemImage: "link")
        }
        .font(.callout)
        .foregroundStyle(.white.opacity(0.9))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tarmac, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var safetyNote: some View {
        Text("Play over a bed or a couch. The insurance claims are fake. Your cracked screen would be very real. Not affiliated with any car company, rocket company, or insurer.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

struct StuntGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STUNT MENU")
                .font(.caption.weight(.heavy))
                .tracking(2)
                .foregroundStyle(.secondary)
            ForEach(StuntKind.allCases) { kind in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.title)
                            .font(.headline)
                        Text(kind.howTo)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(Money.format(Int(kind.baseClaim)))
                            .font(.form(13, weight: .bold))
                        DifficultyDots(level: kind.difficulty)
                    }
                }
                .padding(.vertical, 6)
                if kind != StuntKind.allCases.last {
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
    }
}
