import Foundation

/// One run: four seconds of fuel, every stunt landed in that window, and the claims they filed.
struct GameSession {
    /// Stunts landed within this many seconds of each other build a chain.
    static let chainWindow: TimeInterval = 1.25
    static let maxMultiplier = 3.0

    private(set) var fuel = FuelGauge()
    private(set) var claims: [InsuranceClaim] = []
    /// Stunts in the current chain (0 before the first stunt).
    private(set) var chain = 0
    private(set) var bestChain = 0

    private var detector: StuntDetector
    private var adjuster: InsuranceAdjuster
    private var lastLanding: TimeInterval?

    init(seed: UInt64, thresholds: StuntDetector.Thresholds = StuntDetector.Thresholds()) {
        detector = StuntDetector(thresholds: thresholds)
        adjuster = InsuranceAdjuster(seed: seed)
    }

    var isOver: Bool { fuel.isEmpty }
    var totalClaimed: Int { claims.reduce(0) { $0 + $1.amount } }

    static func multiplier(forChain chain: Int) -> Double {
        min(maxMultiplier, 1 + 0.25 * Double(max(0, chain - 1)))
    }

    /// Ignition. Starts the fuel clock.
    mutating func start(at time: TimeInterval) {
        fuel.burn(to: time)
    }

    mutating func tick(to time: TimeInterval) {
        fuel.burn(to: time)
    }

    /// Feeds one motion sample to the detector and files a claim for anything it lands.
    @discardableResult
    mutating func ingest(_ sample: MotionSample) -> [InsuranceClaim] {
        guard !isOver else { return [] }
        var filed: [InsuranceClaim] = []
        for stunt in detector.process(sample) {
            filed.append(land(stunt))
        }
        return filed
    }

    /// Scores a stunt. Public so the simulator's stunt buttons can skip the sensors.
    @discardableResult
    mutating func land(_ stunt: DetectedStunt) -> InsuranceClaim {
        if let last = lastLanding, stunt.time - last <= Self.chainWindow {
            chain += 1
        } else {
            chain = 1
        }
        lastLanding = stunt.time
        bestChain = max(bestChain, chain)

        let claim = adjuster.file(stunt, chain: chain, multiplier: Self.multiplier(forChain: chain))
        claims.append(claim)
        if stunt.kind.refundsFuel {
            fuel.refund(stunt.landing.fuelRefund)
        }
        return claim
    }

    func report() -> ClaimsReport {
        ClaimsReport(claims: claims, bestChain: bestChain)
    }
}
