import Foundation
import Observation
import UIKit

/// Follows the car, looking ahead of it and zooming out in the air.
struct Camera {
    var x = 0.0
    var y = 6.0
    var metersWide = 50.0
}

/// Claim forms that blow out of the car when it crashes.
struct Paper: Identifiable {
    let id: Int
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var angle: Double
    var spin: Double
}

/// Runs the title → cockpit → claims report loop: steps the sim at a fixed rate every
/// frame, reads tilt, fires haptics on sim events and builds the report at the end.
@Observable
@MainActor
final class GameController {
    enum Phase {
        case title
        case cockpit
        case report
    }

    struct Callout: Equatable {
        let id: Int
        let text: String
        let until: Double
    }

    static let stepSeconds = 1.0 / 120.0

    private(set) var phase: Phase = .title
    private(set) var sim = LaunchSim()
    /// Set by the cockpit's buttons and switches. Spin is filled in from tilt or the rotate buttons.
    var controls = Controls()
    /// -1, 0 or 1 from the on-screen rotate buttons.
    var spinButtons = 0.0
    var useTilt: Bool = UserDefaults.standard.object(forKey: Keys.useTilt) as? Bool ?? true {
        didSet { UserDefaults.standard.set(useTilt, forKey: Keys.useTilt) }
    }

    private(set) var camera = Camera()
    private(set) var papers: [Paper] = []
    private(set) var clock = 0.0
    private(set) var coachLine = ""
    private(set) var callout: Callout?
    private(set) var report: ClaimsReport?
    private(set) var isNewBest = false
    private(set) var bestScore = UserDefaults.standard.integer(forKey: Keys.bestScore) {
        didSet { UserDefaults.standard.set(bestScore, forKey: Keys.bestScore) }
    }

    var tiltAvailable: Bool { tilt.isAvailable }
    var steeringWithTilt: Bool { useTilt && tilt.isAvailable }

    private enum Keys {
        static let bestScore = "bestScore"
        static let useTilt = "useTiltSteering"
    }

    @ObservationIgnored private let tilt = TiltSensor()
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private var driver: FrameDriver?
    @ObservationIgnored private var accumulator = 0.0
    @ObservationIgnored private var finishedAt: Double?
    @ObservationIgnored private var lastRumble = 0.0
    @ObservationIgnored private var calloutCount = 0

    // MARK: - Flow

    func newRun() {
        stopLoop()
        sim = LaunchSim()
        controls = Controls()
        spinButtons = 0
        papers = []
        report = nil
        isNewBest = false
        callout = nil
        finishedAt = nil
        accumulator = 0
        clock = 0
        camera = Camera(x: sim.x + 12, y: 6, metersWide: 50)
        coachLine = Coach.line(for: sim)
        phase = .cockpit

        UIApplication.shared.isIdleTimerDisabled = true
        haptics.prepare()
        tilt.start()
        tilt.recenter()
        let driver = FrameDriver { [weak self] dt in self?.frame(dt) }
        self.driver = driver
        driver.start()
    }

    func toggleFan() {
        controls.fan.toggle()
        haptics.click()
    }

    func recenterTilt() {
        tilt.recenter()
    }

    func quitToTitle() {
        stopLoop()
        phase = .title
    }

    private func stopLoop() {
        driver?.stop()
        driver = nil
        tilt.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Frame

    private func frame(_ dt: Double) {
        let dt = min(dt, 0.1)
        clock += dt

        var input = controls
        input.spin = steeringWithTilt ? TiltSteering.spin(wheelAngleDegrees: tilt.wheelAngle) : spinButtons
        accumulator += dt
        while accumulator >= Self.stepSeconds {
            sim.step(Self.stepSeconds, controls: input)
            accumulator -= Self.stepSeconds
        }

        for event in sim.drainEvents() {
            handle(event)
        }
        if (sim.boostFiring || sim.liftFiring) && clock - lastRumble > 0.06 {
            lastRumble = clock
            haptics.rumble(sim.boostFiring && sim.liftFiring ? 1 : 0.6)
        }

        updateCamera(dt)
        updatePapers(dt)
        coachLine = Coach.line(for: sim)

        if let finishedAt, clock - finishedAt > 1.2 {
            finish()
        }
    }

    private func handle(_ event: SimEvent) {
        switch event {
        case .launched:
            haptics.thump()
            show("LAUNCH")
        case .hitSixty(let seconds):
            show("0–60 IN \(String(format: "%.2f", seconds)) S")
            if seconds < Scorer.revealSixtyTime { haptics.success() }
        case .fanOverheated:
            haptics.warning()
            show("FAN OVERHEAT")
        case .fanRecovered:
            haptics.click()
        case .outOfAir:
            haptics.warning()
            show("AIR TANKS EMPTY")
        case .enteredLoop:
            break
        case .completedLoop:
            haptics.success()
            show("LOOP!")
        case .fellOffLoop:
            haptics.warning()
            show("LOST GRIP")
        case .tookOff:
            haptics.thump()
            show("AIRBORNE")
        case .cleared:
            haptics.click()
            show("CLEARED \(sim.clearedCount)/\(sim.course.vehicles.count)")
        case .landed(let impact):
            haptics.thump()
            haptics.success()
            show(Scorer.landingGrade(impact: impact) == .greased ? "GREASED IT" : "LANDED")
        case .crashed:
            haptics.crash()
            show("TOTALED")
            spawnPapers()
        case .finished:
            finishedAt = clock
        }
    }

    private func show(_ text: String) {
        calloutCount += 1
        callout = Callout(id: calloutCount, text: text, until: clock + 1.3)
    }

    private func finish() {
        stopLoop()
        var adjuster = InsuranceAdjuster(seed: UInt64.random(in: .min ... .max))
        let report = ClaimsReport(claims: adjuster.fileAll(Scorer.stunts(from: sim)))
        if report.score > bestScore {
            bestScore = report.score
            isNewBest = true
        }
        self.report = report
        phase = .report
    }

    // MARK: - Camera and effects

    private func updateCamera(_ dt: Double) {
        let airborne = sim.segment == .air || sim.segment == .crashed
        let lookAhead = min(14, max(4, sim.speed * 0.35))
        let targetX = sim.x + (sim.segment == .loop ? 0 : lookAhead)
        let targetY = max(6, sim.y + 2)
        let targetWidth = airborne ? 72.0 : sim.segment == .loop ? 58 : 50
        let blend = 1 - exp(-dt * 4)
        camera.x += (targetX - camera.x) * blend
        camera.y += (targetY - camera.y) * blend
        camera.metersWide += (targetWidth - camera.metersWide) * (1 - exp(-dt * 2))
    }

    private func spawnPapers() {
        papers = (0..<28).map { index in
            Paper(
                id: index,
                x: sim.x,
                y: sim.y + 1,
                vx: sim.vx * 0.3 + Double.random(in: -6...6),
                vy: Double.random(in: 3...11),
                angle: Double.random(in: 0...(2 * .pi)),
                spin: Double.random(in: -8...8)
            )
        }
    }

    private func updatePapers(_ dt: Double) {
        guard !papers.isEmpty else { return }
        for index in papers.indices {
            var paper = papers[index]
            let ground = sim.course.ground(at: paper.x).height
            if paper.y <= ground {
                paper.y = ground
                paper.vx = 0
                paper.vy = 0
                paper.spin = 0
            } else {
                // Paper falls slowly and drifts.
                paper.vy = max(paper.vy - 6 * dt, -2.5)
                paper.vx *= 1 - min(1, 1.5 * dt)
                paper.x += paper.vx * dt
                paper.y += paper.vy * dt
                paper.angle += paper.spin * dt
            }
            papers[index] = paper
        }
    }
}
