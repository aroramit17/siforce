import Foundation

/// SplitMix64. Seeded so a run's claims can be replayed in tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum ClaimStatus: Equatable {
    case approved
    case denied(reason: String)
    case underReview

    var stamp: String {
        switch self {
        case .approved: return "APPROVED"
        case .denied: return "DENIED"
        case .underReview: return "UNDER REVIEW"
        }
    }
}

struct InsuranceClaim: Identifiable, Equatable {
    /// The claim number, e.g. "RSC-4821-03".
    let id: String
    let stunt: DetectedStunt
    /// How many stunts in a row this one finished (1 when it stands alone).
    let chain: Int
    let multiplier: Double
    /// Dollars claimed.
    let amount: Int
    let description: String
    let adjusterNote: String
    let status: ClaimStatus

    var payout: Int { status == .approved ? amount : 0 }
}

/// Files a fake insurance claim for every stunt.
struct InsuranceAdjuster {
    private var rng: SeededGenerator
    private var filed = 0

    init(seed: UInt64) {
        rng = SeededGenerator(seed: seed)
    }

    mutating func file(_ stunt: DetectedStunt, chain: Int, multiplier: Double) -> InsuranceClaim {
        filed += 1
        let jitter = Double.random(in: 0.9...1.15, using: &rng)
        let amount = Int((stunt.kind.baseClaim * stunt.landing.claimMultiplier * multiplier * jitter).rounded())
        let serial = Int.random(in: 1000...9999, using: &rng)

        return InsuranceClaim(
            id: String(format: "RSC-%04d-%02d", serial, filed),
            stunt: stunt,
            chain: chain,
            multiplier: multiplier,
            amount: amount,
            description: pick(Self.descriptions(for: stunt.kind)),
            adjusterNote: pick(Self.notes(for: stunt.landing)),
            status: decide()
        )
    }

    private mutating func decide() -> ClaimStatus {
        let roll = Double.random(in: 0..<1, using: &rng)
        if roll < 0.55 { return .approved }
        if roll < 0.80 { return .denied(reason: pick(Self.denialReasons)) }
        return .underReview
    }

    private mutating func pick(_ options: [String]) -> String {
        options.randomElement(using: &rng) ?? ""
    }

    // MARK: - Paperwork

    static func descriptions(for kind: StuntKind) -> [String] {
        switch kind {
        case .ramp:
            return [
                "Vehicle achieved altitude. Policy does not cover altitude.",
                "Claimant describes the ramp as \"mostly decorative.\"",
                "Front bumper briefly saw the sky and has not been the same since.",
            ]
        case .kickflip:
            return [
                "Vehicle rotated 360° on its long axis. Cupholders emptied in all directions.",
                "Claimant states the car \"wanted to.\"",
                "Roof and road traded places, then traded back.",
            ]
        case .doubleKickflip:
            return [
                "Two complete rolls. Adjuster requested a third for the brochure.",
                "Vehicle rolled twice. Passenger seat has filed its own claim.",
                "Witnesses report \"a sports car doing a fidget spinner impression.\"",
            ]
        case .treFlip:
            return [
                "Simultaneous roll and spin. Our actuaries have gone home for the day.",
                "Vehicle flipped and rotated at once. Physics has been notified.",
                "Claimant insists this is \"a skateboard thing.\" It is a car.",
            ]
        case .backflip:
            return [
                "End-over-end rotation. The trunk is now the frunk.",
                "Vehicle performed a backflip. Headlights saw the taillights.",
                "Full flip. The glovebox is somewhere in the back seat.",
            ]
        case .donut:
            return [
                "Vehicle performed a donut in an area not zoned for donuts.",
                "One full rotation. Tire marks spell out a word we can't print.",
                "Claimant was \"just checking the mirrors from every angle.\"",
            ]
        case .launch:
            return [
                "Vehicle left the ground on purpose. Thrusters were not on the policy.",
                "Sudden vertical acceleration. Air traffic control would like a word.",
                "Car went up. Claimant is \"pretty sure\" it came back down.",
            ]
        case .hover:
            return [
                "Vehicle hovered for one full second. This is not a feature we insure.",
                "Car floated motionless. Claimant described it as \"vibing.\"",
                "Sustained levitation. Adjuster has questions about the cold gas thrusters.",
            ]
        }
    }

    static func notes(for landing: LandingGrade) -> [String] {
        switch landing {
        case .greased:
            return [
                "Honestly? Beautiful.",
                "Adjuster gave a standing ovation, which is not standard procedure.",
                "Clean enough to put in the brochure.",
            ]
        case .clean:
            return [
                "Landed. Mostly.",
                "No notes. Several concerns.",
                "Acceptable. Please don't do it again. Please do it again.",
            ]
        case .sketchy:
            return [
                "Witnesses describe the landing as \"a choice.\"",
                "The car is fine. The vibes are not.",
                "Landed on what we will generously call wheels.",
            ]
        }
    }

    static let denialReasons = [
        "Act of Marketing",
        "Pre-existing levitation",
        "Vehicle was, technically, a phone",
        "Stunt not performed on a closed course",
        "Policy excludes rocket thrusters",
        "Claimant was visibly having fun",
        "See fine print, page 4,000",
    ]
}
