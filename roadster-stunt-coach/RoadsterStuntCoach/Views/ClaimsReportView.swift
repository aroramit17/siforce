import SwiftUI

struct ClaimsReportView: View {
    @EnvironmentObject private var game: GameController

    var body: some View {
        if let report = game.report {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    summary(report)
                    verdict(report)
                    if report.claims.isEmpty {
                        Text("No claims filed. Your premium is safe. Your dignity is intact. Boring.")
                            .font(.form(15))
                            .foregroundStyle(Color.claimInk)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(report.claims) { claim in
                            ClaimCardView(claim: claim)
                        }
                    }
                    Text("Roadster Stunt Mutual is not a real insurer. No claims will be paid. Several will be laughed at.")
                        .font(.form(11))
                        .foregroundStyle(Color.claimInk.opacity(0.6))
                }
                .padding(20)
                .background(Color.claimPaper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) { actions(report) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CLAIMS REPORT")
                .font(.form(26, weight: .heavy))
            Text("Roadster Stunt Mutual · Form RSC-4S")
                .font(.form(12))
            Text(Date.now.formatted(date: .abbreviated, time: .shortened))
                .font(.form(12))
                .opacity(0.7)
        }
        .foregroundStyle(Color.claimInk)
    }

    private func summary(_ report: ClaimsReport) -> some View {
        VStack(spacing: 8) {
            row("Total claimed", Money.format(report.totalClaimed), bold: true)
            row("Actually paid", Money.format(report.totalPaid))
            row("Claims denied", "\(report.deniedCount) of \(report.claims.count)")
            row("Premium increase", "+\(report.premiumIncreasePercent)%")
            row("Longest chain", report.bestChain > 1 ? "×\(report.bestChain)" : "—")
        }
        .font(.form(15))
        .foregroundStyle(Color.claimInk)
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.claimInk.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private func row(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .opacity(0.7)
            Spacer(minLength: 16)
            Text(value)
                .fontWeight(bold ? .heavy : .semibold)
        }
    }

    private func verdict(_ report: ClaimsReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if game.isNewBest {
                Text("NEW PERSONAL WORST")
                    .font(.form(12, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.roadsterRed, in: Capsule())
            }
            Text("COACH'S VERDICT")
                .font(.form(12, weight: .heavy))
                .opacity(0.7)
            Text(report.rank.title)
                .font(.poster(28))
                .foregroundStyle(Color.roadsterRed)
            Text("“\(report.rank.coachSays)”")
                .font(.form(14))
        }
        .foregroundStyle(Color.claimInk)
    }

    private func actions(_ report: ClaimsReport) -> some View {
        VStack(spacing: 10) {
            Button("RUN IT BACK") { game.startRun() }
                .buttonStyle(BigButtonStyle())
            HStack(spacing: 10) {
                ShareLink(item: report.shareText) {
                    Label("Share claims", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    game.showTitle()
                } label: {
                    Label("Garage", systemImage: "house.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

struct ClaimCardView: View {
    let claim: InsuranceClaim

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("CLAIM #\(claim.id)")
                    .font(.form(12, weight: .bold))
                    .opacity(0.7)
                Spacer()
                Text(Money.format(claim.amount))
                    .font(.form(17, weight: .heavy))
            }
            HStack(spacing: 8) {
                Text(claim.stunt.kind.title)
                    .font(.headline)
                Text(claim.stunt.landing.title.uppercased())
                    .font(.form(11, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Color.claimInk.opacity(0.4)))
                if claim.chain > 1 {
                    Text("CHAIN ×\(claim.chain)")
                        .font(.form(11, weight: .heavy))
                        .foregroundStyle(Color.roadsterRed)
                }
            }
            Text(claim.description)
                .font(.form(13))
                .fixedSize(horizontal: false, vertical: true)
            Text("Adjuster: \(claim.adjusterNote)")
                .font(.form(13).italic())
                .opacity(0.75)
                .fixedSize(horizontal: false, vertical: true)
            if case .denied(let reason) = claim.status {
                Text("Reason for denial: \(reason).")
                    .font(.form(13, weight: .semibold))
                    .foregroundStyle(Color.roadsterRed)
            }
        }
        .foregroundStyle(Color.claimInk)
        .padding([.horizontal, .top], 14)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .bottomTrailing) {
            StampView(status: claim.status)
                .padding(10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(claim.status.stamp)
    }
}

struct StampView: View {
    let status: ClaimStatus

    var body: some View {
        Text(status.stamp)
            .font(.form(15, weight: .black))
            .tracking(2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(lineWidth: 2.5))
            .foregroundStyle(status.color.opacity(0.75))
            .rotationEffect(.degrees(-12))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
