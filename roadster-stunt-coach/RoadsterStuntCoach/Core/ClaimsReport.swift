import Foundation

enum CoachRank: CaseIterable {
    case parked
    case learnersPermit
    case weekendStuntDriver
    case closedCoursePro
    case uninsurable

    static func forTotal(_ dollars: Int) -> CoachRank {
        switch dollars {
        case ..<1: return .parked
        case ..<15_000: return .learnersPermit
        case ..<45_000: return .weekendStuntDriver
        case ..<100_000: return .closedCoursePro
        default: return .uninsurable
        }
    }

    var title: String {
        switch self {
        case .parked: return "Never Left the Showroom"
        case .learnersPermit: return "Learner's Permit"
        case .weekendStuntDriver: return "Weekend Stunt Driver"
        case .closedCoursePro: return "Professional Driver, Closed Course"
        case .uninsurable: return "Uninsurable"
        }
    }

    var coachSays: String {
        switch self {
        case .parked: return "Four seconds of fuel and you spent them admiring the paint."
        case .learnersPermit: return "You left the ground. Technically. Let's call it a start."
        case .weekendStuntDriver: return "Respectable. Your insurer has started a group chat about you."
        case .closedCoursePro: return "That was a launch event. Somebody get this on a big screen."
        case .uninsurable: return "No company on Earth will cover you. Maybe try orbit."
        }
    }
}

struct ClaimsReport {
    let claims: [InsuranceClaim]
    let bestChain: Int

    var totalClaimed: Int { claims.reduce(0) { $0 + $1.amount } }
    var totalPaid: Int { claims.reduce(0) { $0 + $1.payout } }
    var deniedCount: Int {
        claims.filter { if case .denied = $0.status { return true } else { return false } }.count
    }
    var premiumIncreasePercent: Int { min(9_999, totalClaimed / 200) }
    var rank: CoachRank { CoachRank.forTotal(totalClaimed) }

    var shareText: String {
        guard !claims.isEmpty else {
            return "I had 4 seconds of fuel in Roadster Stunt Coach and filed zero insurance claims. My premium is safe. My dignity is not."
        }
        let tricks = claims.map(\.stunt.kind.title).joined(separator: ", ")
        return """
        Roadster Stunt Coach: \(Money.format(totalClaimed)) in insurance claims in 4 seconds.
        Stunts: \(tricks).
        Paid out: \(Money.format(totalPaid)). Premium: +\(premiumIncreasePercent)%.
        Rank: \(rank.title).
        """
    }
}

enum Money {
    /// "$12,750". Hand-rolled so the core doesn't depend on locale formatting.
    static func format(_ dollars: Int) -> String {
        let digits = String(dollars.magnitude)
        var grouped = ""
        for (index, digit) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        return (dollars < 0 ? "-$" : "$") + grouped
    }
}
