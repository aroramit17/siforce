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
    let stunt: Stunt
    /// Dollars claimed.
    let amount: Int
    let description: String
    let adjusterNote: String
    let status: ClaimStatus

    var payout: Int { status == .approved ? amount : 0 }
}

/// Files a fake insurance claim for every stunt.
struct InsuranceAdjuster {
    static let noDriverDenial = "There was no driver. The car filed this claim itself"

    private var rng: SeededGenerator
    private var filed = 0

    init(seed: UInt64) {
        rng = SeededGenerator(seed: seed)
    }

    mutating func file(_ stunt: Stunt) -> InsuranceClaim {
        filed += 1
        let jitter = Double.random(in: 0.9...1.15, using: &rng)
        let amount = Int((stunt.kind.baseClaim * Double(stunt.count) * stunt.grade.claimMultiplier * jitter).rounded())
        let serial = Int.random(in: 1000...9999, using: &rng)

        let description: String
        let status: ClaimStatus
        if let reason = stunt.crash {
            description = pick(Self.crashDescriptions(for: reason))
            status = .denied(reason: Self.noDriverDenial)
        } else {
            description = pick(Self.descriptions(for: stunt.kind))
            status = decide()
        }

        return InsuranceClaim(
            id: String(format: "RSC-%04d-%02d", serial, filed),
            stunt: stunt,
            amount: amount,
            description: description,
            adjusterNote: pick(Self.notes(for: stunt.grade)),
            status: status
        )
    }

    mutating func fileAll(_ stunts: [Stunt]) -> [InsuranceClaim] {
        var claims: [InsuranceClaim] = []
        for stunt in stunts {
            claims.append(file(stunt))
        }
        return claims
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
        case .launch:
            return [
                "Vehicle reached 60 mph before the claimant finished saying \"go.\"",
                "Rear thrusters fired on a public-ish runway. Several eyebrows left the ground.",
                "Acceleration so sudden the paint is still at the starting line.",
            ]
        case .loop:
            return [
                "Vehicle drove on the ceiling. We do not have a form for the ceiling.",
                "Suction fans held the car upside down. Cupholders did not get the memo.",
                "Claimant describes the loop as \"basically a very round road.\"",
            ]
        case .hop:
            return [
                "Vehicle jumped a row of parked vehicles. The parked vehicles were not consulted.",
                "Five-car hop. The Semi driver has requested therapy.",
                "Airborne over a parking lot. Parking enforcement is reviewing the footage.",
            ]
        case .backflip:
            return [
                "Full backflip. The trunk saw the sky, then the ground, then the sky again.",
                "Vehicle rotated end over end. Headlights briefly became taillights.",
                "Claimant says the car \"just wanted to see behind itself.\"",
            ]
        case .frontflip:
            return [
                "Frontflip. The frunk is now emotionally the trunk.",
                "Vehicle somersaulted forward. The glovebox is somewhere in the back seat.",
                "Nose-first rotation. Our actuaries have gone home for the day.",
            ]
        case .landing:
            return [
                "Underbody thrusters fired to soften the landing. The ground was grateful.",
                "Vehicle descended on a column of compressed air like a very expensive leaf.",
                "Touchdown. Mission control has requested the car not do that again. Or do.",
            ]
        case .totaled:
            return ["Vehicle is now several smaller vehicles."]
        }
    }

    static func crashDescriptions(for reason: CrashReason) -> [String] {
        switch reason {
        case .fellOffLoop:
            return [
                "Vehicle detached from the ceiling of the loop. Ceiling unharmed.",
                "Suction was described as \"more of a suggestion.\" Gravity disagreed.",
            ]
        case .stalled:
            return [
                "Vehicle ran out of momentum halfway up a ramp and reconsidered its choices.",
                "Car stopped on a slope and then, inevitably, stopped being on the slope.",
            ]
        case .hitVehicle(let name):
            return [
                "Vehicle landed on the parked \(name). The \(name) has filed a counterclaim.",
                "Claimant cleared every vehicle except the \(name), which was \"in the way.\"",
            ]
        case .hitRampWall:
            return [
                "Vehicle met the landing ramp from the side the landing ramp is not for.",
                "Came up short. The back of the landing ramp is now an abstract sculpture.",
            ]
        case .onRoof:
            return [
                "Vehicle landed on its roof. The roof was not rated for this.",
                "Upside-down landing. Technically all four wheels were in the air.",
            ]
        case .wrongAngle:
            return [
                "Vehicle met the ground at an angle the ground did not agree with.",
                "Landed nose-first. The nose has filed a separate claim.",
            ]
        case .hardLanding:
            return [
                "Vehicle arrived at the ground faster than the ground was expecting.",
                "Touchdown at speed. The suspension has retired.",
            ]
        }
    }

    static func notes(for grade: Grade) -> [String] {
        switch grade {
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
                "Witnesses describe it as \"a choice.\"",
                "The car is fine. The vibes are not.",
                "We will generously call this an outcome.",
            ]
        }
    }

    static let denialReasons = [
        "Act of Marketing",
        "Pre-existing levitation",
        "Policy excludes cold-gas thrusters",
        "Stunt not performed on a closed course",
        "Claimant was visibly having fun",
        "Vehicle was, technically, a rocket",
        "See fine print, page 4,000",
    ]
}
