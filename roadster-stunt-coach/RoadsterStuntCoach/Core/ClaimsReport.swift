import Foundation

enum CoachRank: CaseIterable {
    case parked
    case learnersPermit
    case weekendStuntDriver
    case closedCoursePro
    case uninsurable

    static func forScore(_ dollars: Int) -> CoachRank {
        switch dollars {
        case ..<1: return .parked
        case ..<20_000: return .learnersPermit
        case ..<55_000: return .weekendStuntDriver
        case ..<95_000: return .closedCoursePro
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
        case .parked: return "You had rocket thrusters and you spent the run admiring the paint."
        case .learnersPermit: return "It moved. It left the ground, briefly. Arm the fan before the loop next time."
        case .weekendStuntDriver: return "Respectable. Your insurer has started a group chat about you."
        case .closedCoursePro: return "That was a reveal event. Somebody get this on a big screen."
        case .uninsurable: return "No company on Earth will cover you. Maybe try orbit."
        }
    }
}

struct ClaimsReport {
    let claims: [InsuranceClaim]

    /// Claims for stunts. The totaled claim is denied and doesn't count.
    var stuntClaims: [InsuranceClaim] { claims.filter { $0.stunt.kind != .totaled } }
    var totaled: InsuranceClaim? { claims.first { $0.stunt.kind == .totaled } }
    var landed: Bool { totaled == nil && claims.contains { $0.stunt.kind == .landing } }

    var score: Int { stuntClaims.reduce(0) { $0 + $1.amount } }
    var totalPaid: Int { stuntClaims.reduce(0) { $0 + $1.payout } }
    var deniedCount: Int {
        claims.filter { if case .denied = $0.status { return true } else { return false } }.count
    }
    var premiumIncreasePercent: Int { min(9_999, (score + (totaled?.amount ?? 0)) / 400) }
    var rank: CoachRank { CoachRank.forScore(score) }

    var shareText: String {
        guard !stuntClaims.isEmpty else {
            return "I took the reveal Roadster to the line in Roadster Stunt Coach and filed zero insurance claims. The car is fine. My pride is not."
        }
        let lines = stuntClaims.map { "• \($0.stunt.kind.title): \($0.stunt.detail)" }.joined(separator: "\n")
        let ending = totaled.map { "Then: \($0.stunt.detail.lowercased()). Totaled." } ?? "Stuck the landing."
        return """
        Roadster Stunt Coach: \(Money.format(score)) in insurance claims.
        \(lines)
        \(ending)
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
