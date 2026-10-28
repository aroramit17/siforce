import SwiftUI
import UIKit

/// Runs the title → countdown → run → claims report loop and bridges sensors, timers and
/// haptics to the pure `GameSession`.
@MainActor
final class GameController: ObservableObject {
    enum Phase: Equatable {
        case title
        case countdown(Int)
        case running
        case finished
    }

    @Published private(set) var phase: Phase = .title
    @Published private(set) var fuelRemaining: TimeInterval = FuelGauge.capacity
    @Published private(set) var claims: [InsuranceClaim] = []
    @Published private(set) var chain = 0
    @Published private(set) var coachLine = CoachLines.ignition.randomElement() ?? ""
    @Published private(set) var report: ClaimsReport?
    @Published private(set) var isNewBest = false
    @Published private(set) var bestTotal: Int = UserDefaults.standard.integer(forKey: Keys.bestTotal) {
        didSet { UserDefaults.standard.set(bestTotal, forKey: Keys.bestTotal) }
    }

    var latestClaim: InsuranceClaim? { claims.last }
    var totalClaimed: Int { claims.reduce(0) { $0 + $1.amount } }
    var motionAvailable: Bool { motion.isAvailable }

    private enum Keys {
        static let bestTotal = "bestTotalClaimed"
    }

    private var session = GameSession(seed: 0)
    private let motion = MotionEngine()
    private let haptics = Haptics()
    private var timer: Timer?
    private var countdownTask: Task<Void, Never>?

    func startRun() {
        stopEverything()
        session = GameSession(seed: UInt64.random(in: .min ... .max))
        fuelRemaining = FuelGauge.capacity
        claims = []
        chain = 0
        report = nil
        isNewBest = false
        coachLine = CoachLines.countdown.randomElement() ?? ""
        UIApplication.shared.isIdleTimerDisabled = true
        haptics.prepare()

        countdownTask = Task { [weak self] in
            for count in stride(from: 3, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.phase = .countdown(count)
                self.haptics.countdown()
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.ignite()
        }
    }

    /// Back to the garage without a report.
    func abandonRun() {
        stopEverything()
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .title
    }

    func showTitle() {
        phase = .title
    }

    /// Simulator stand-in for the sensors: lands a stunt with a random landing.
    func fakeStunt(_ kind: StuntKind) {
        guard phase == .running else { return }
        let landing: LandingGrade = [.greased, .clean, .clean, .sketchy].randomElement() ?? .clean
        let stunt = DetectedStunt(kind: kind, time: ProcessInfo.processInfo.systemUptime, landing: landing, degrees: 0)
        celebrate(session.land(stunt))
    }

    // MARK: - Run loop

    private func ignite() {
        countdownTask = nil
        phase = .running
        coachLine = CoachLines.ignition.randomElement() ?? ""
        session.start(at: ProcessInfo.processInfo.systemUptime)
        haptics.ignition()

        motion.start { [weak self] sample in
            self?.handle(sample)
        }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func handle(_ sample: MotionSample) {
        guard phase == .running else { return }
        for claim in session.ingest(sample) {
            celebrate(claim)
        }
    }

    private func tick() {
        guard phase == .running else { return }
        session.tick(to: ProcessInfo.processInfo.systemUptime)
        fuelRemaining = session.fuel.remaining
        if session.isOver { finish() }
    }

    private func celebrate(_ claim: InsuranceClaim) {
        claims = session.claims
        chain = session.chain
        fuelRemaining = session.fuel.remaining
        coachLine = CoachLines.after(claim).randomElement() ?? ""
        haptics.landed(claim.stunt.landing)
    }

    private func finish() {
        stopEverything()
        UIApplication.shared.isIdleTimerDisabled = false
        let report = session.report()
        if report.totalClaimed > bestTotal {
            bestTotal = report.totalClaimed
            isNewBest = true
        }
        self.report = report
        haptics.outOfFuel()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            phase = .finished
        }
    }

    private func stopEverything() {
        countdownTask?.cancel()
        countdownTask = nil
        timer?.invalidate()
        timer = nil
        motion.stop()
    }
}

enum CoachLines {
    static let countdown = [
        "Grip it like a tiny steering wheel.",
        "Over a bed. Over a couch. Not over concrete.",
        "Fuel is four seconds. The launch window is now.",
    ]

    static let ignition = [
        "GO GO GO!",
        "Send it!",
        "Fuel's burning! Move!",
    ]

    static func after(_ claim: InsuranceClaim) -> [String] {
        if claim.chain >= 3 {
            return ["CHAIN IT! Don't stop now!", "The adjuster is sweating!", "Combo! Keep it rolling!"]
        }
        switch claim.stunt.landing {
        case .greased:
            return ["That's going in the brochure!", "Greased it!", "Textbook. Illegal, but textbook."]
        case .clean:
            return ["Nice! Again!", "Clean! Now something harder.", "Good! Chain the next one!"]
        case .sketchy:
            return ["Commit to the landing!", "Wheels DOWN next time!", "Sketchy! Finish the rotation!"]
        }
    }
}
