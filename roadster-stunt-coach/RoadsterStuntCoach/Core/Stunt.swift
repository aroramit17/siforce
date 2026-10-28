import Foundation

enum StuntKind: String, CaseIterable, Identifiable {
    case launch
    case loop
    case hop
    case backflip
    case frontflip
    case landing
    case totaled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .launch: return "The Launch"
        case .loop: return "The Loop"
        case .hop: return "The Five-Car Hop"
        case .backflip: return "The Backflip"
        case .frontflip: return "The Frontflip"
        case .landing: return "The Thruster Landing"
        case .totaled: return "Totaled"
        }
    }

    /// Dollars before the grade multiplier, per stunt (per vehicle for the hop, per flip for flips).
    var baseClaim: Double {
        switch self {
        case .launch: return 5_000
        case .loop: return 12_000
        case .hop: return 4_000
        case .backflip: return 15_000
        case .frontflip: return 18_000
        case .landing: return 10_000
        case .totaled: return 250_000
        }
    }
}

enum Grade: String {
    case greased
    case clean
    case sketchy

    var title: String {
        switch self {
        case .greased: return "Greased"
        case .clean: return "Clean"
        case .sketchy: return "Sketchy"
        }
    }

    var claimMultiplier: Double {
        switch self {
        case .greased: return 1.5
        case .clean: return 1.0
        case .sketchy: return 0.6
        }
    }
}

struct Stunt: Equatable {
    var kind: StuntKind
    var grade: Grade
    /// One line of numbers for the claim form, e.g. "0–60 mph in 0.79 s".
    var detail: String
    /// Vehicles cleared for the hop, flips for flips; 1 otherwise.
    var count = 1
    var crash: CrashReason?
}

enum Scorer {
    /// The reveal's claimed 0–60 time.
    static let revealSixtyTime = 0.81

    /// Everything a finished (or crashed) run earns, in the order it happened.
    static func stunts(from sim: LaunchSim) -> [Stunt] {
        var stunts: [Stunt] = []

        if let sixty = sim.sixtyTime {
            let grade: Grade = sixty < revealSixtyTime ? .greased : sixty < 1.5 ? .clean : .sketchy
            var detail = "0–60 mph in \(String(format: "%.2f", sixty)) s"
            if grade == .greased { detail += ", beating the reveal's 0.81 s" }
            stunts.append(Stunt(kind: .launch, grade: grade, detail: detail))
        }

        if sim.loopCompleted {
            let grip = max(0, sim.minLoopGrip)
            let grade: Grade = grip <= 1 ? .greased : .clean
            stunts.append(Stunt(
                kind: .loop,
                grade: grade,
                detail: "Upside down with \(String(format: "%.1f", grip)) g of grip to spare"
            ))
        }

        if sim.clearedCount > 0 {
            let total = sim.course.vehicles.count
            let grade: Grade = sim.clearedCount == total ? .greased : sim.clearedCount >= 3 ? .clean : .sketchy
            stunts.append(Stunt(
                kind: .hop,
                grade: grade,
                detail: "Cleared \(sim.clearedCount) of \(total) parked vehicles",
                count: sim.clearedCount
            ))
        }

        if sim.landed, let impact = sim.landingImpact {
            let grade = landingGrade(impact: impact)
            let flips = sim.flips
            if flips != 0 {
                let kind: StuntKind = flips > 0 ? .backflip : .frontflip
                let times = abs(flips) == 1 ? "" : " ×\(abs(flips))"
                stunts.append(Stunt(kind: kind, grade: grade, detail: "\(kind.title)\(times), landed", count: abs(flips)))
            }
            stunts.append(Stunt(
                kind: .landing,
                grade: grade,
                detail: "Touched down at \(String(format: "%.1f", impact)) m/s"
            ))
        }

        if let reason = sim.crashReason {
            stunts.append(Stunt(kind: .totaled, grade: .sketchy, detail: crashSummary(reason), crash: reason))
        }
        return stunts
    }

    static func landingGrade(impact: Double) -> Grade {
        if impact <= 3.5 { return .greased }
        if impact <= 6 { return .clean }
        return .sketchy
    }

    static func crashSummary(_ reason: CrashReason) -> String {
        switch reason {
        case .fellOffLoop: return "Fell off the ceiling of the loop"
        case .stalled: return "Stalled on the ramp"
        case .hitVehicle(let name): return "Landed on the \(name)"
        case .hitRampWall: return "Hit the back of the landing ramp"
        case .onRoof: return "Landed on the roof"
        case .wrongAngle: return "Landed at the wrong angle"
        case .hardLanding: return "Landed too hard"
        }
    }
}
