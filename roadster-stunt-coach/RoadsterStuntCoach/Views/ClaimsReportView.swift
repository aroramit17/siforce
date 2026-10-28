import SwiftUI

struct ClaimsReportView: View {
    @Environment(GameController.self) private var game

    var body: some View {
        if let report = game.report {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        summary(report)
                        verdict(report)
                    }
                    .padding(18)
                }
                .frame(maxWidth: 330)
                .background(Color.claimPaper)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if report.claims.isEmpty {
                            Text("No claims filed. The car never left the staging line. Your premium is safe. Boring.")
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
                        actions(report)
                    }
                    .padding(18)
                }
                .background(Color.claimPaper.opacity(0.92))
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CLAIMS REPORT")
                .font(.form(24, weight: .heavy))
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
            row("Stunt claims", Money.format(report.score), bold: true)
            row("Actually paid", Money.format(report.totalPaid))
            row("Claims denied", "\(report.deniedCount) of \(report.claims.count)")
            row("Premium increase", "+\(report.premiumIncreasePercent)%")
            row("Outcome", report.landed ? "Stuck the landing" : "Totaled")
        }
        .font(.form(14))
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
                .font(.poster(26))
                .foregroundStyle(Color.roadsterRed)
            Text("“\(report.rank.coachSays)”")
                .font(.form(13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.claimInk)
    }

    private func actions(_ report: ClaimsReport) -> some View {
        VStack(spacing: 10) {
            Button("RUN IT BACK") { game.newRun() }
                .buttonStyle(BigButtonStyle())
            HStack(spacing: 10) {
                ShareLink(item: report.shareText) {
                    Label("Share claims", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    game.quitToTitle()
                } label: {
                    Label("Garage", systemImage: "house.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.claimInk)
        }
        .padding(.top, 6)
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
                if claim.stunt.kind != .totaled {
                    Text(claim.stunt.grade.title.uppercased())
                        .font(.form(11, weight: .heavy))
                        .foregroundStyle(claim.stunt.grade.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Color.claimInk.opacity(0.4)))
                }
            }
            Text(claim.stunt.detail)
                .font(.form(12, weight: .semibold))
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
