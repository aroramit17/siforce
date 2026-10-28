import Foundation

enum StuntKind: String, CaseIterable, Identifiable, Codable {
    case ramp
    case kickflip
    case doubleKickflip
    case treFlip
    case backflip
    case donut
    case launch
    case hover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ramp: return "The Ramp"
        case .kickflip: return "The Kickflip"
        case .doubleKickflip: return "The Double Kickflip"
        case .treFlip: return "The Tre Flip"
        case .backflip: return "The Backflip"
        case .donut: return "The Donut"
        case .launch: return "The Launch"
        case .hover: return "The Hover"
        }
    }

    var howTo: String {
        switch self {
        case .ramp: return "Snap the nose of the phone up past 40°, then bring it back down."
        case .kickflip: return "Roll the phone a full 360° along its long edge."
        case .doubleKickflip: return "Two full rolls. Over a bed. We mean it."
        case .treFlip: return "A kickflip with a half spin thrown in at the same time."
        case .backflip: return "Flip it end over end, a full 360°."
        case .donut: return "Turn it a full 360° like a steering wheel, or spin it flat on a table."
        case .launch: return "Jolt it straight up, fast. Keep holding on."
        case .hover: return "Hold it dead still for one full second. Burns fuel, files a big claim."
        }
    }

    /// 1 (anyone) to 5 (your screen protector has filed a complaint).
    var difficulty: Int {
        switch self {
        case .ramp, .hover: return 1
        case .launch, .donut: return 2
        case .kickflip, .backflip: return 3
        case .treFlip: return 4
        case .doubleKickflip: return 5
        }
    }

    /// Base insurance claim in dollars, before landing and combo multipliers.
    var baseClaim: Double {
        switch self {
        case .ramp: return 1_200
        case .donut: return 4_200
        case .launch: return 6_500
        case .kickflip: return 8_500
        case .hover: return 9_999
        case .backflip: return 14_000
        case .doubleKickflip: return 22_000
        case .treFlip: return 31_000
        }
    }

    /// Landing a real trick puts a little fuel back. Hovering and launching only burn it.
    var refundsFuel: Bool {
        switch self {
        case .launch, .hover: return false
        default: return true
        }
    }
}

enum LandingGrade: String, Codable {
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

    /// Seconds of fuel returned by regenerative braking.
    var fuelRefund: TimeInterval {
        switch self {
        case .greased: return 0.3
        case .clean: return 0.15
        case .sketchy: return 0
        }
    }
}

struct DetectedStunt: Equatable {
    var kind: StuntKind
    var time: TimeInterval
    var landing: LandingGrade
    /// Peak rotation on the stunt's main axis, in degrees. Zero for launches and hovers.
    var degrees: Double
}
