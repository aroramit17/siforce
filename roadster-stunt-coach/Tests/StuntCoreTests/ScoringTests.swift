import XCTest
@testable import StuntCore

final class ScoringTests: XCTestCase {
    func testCleanRunEarnsLaunchLoopHopAndLanding() {
        let (sim, _) = Pilots.fly(Pilots.fanThroughTheLoop)
        let stunts = Scorer.stunts(from: sim)
        XCTAssertEqual(stunts.map(\.kind), [.launch, .loop, .hop, .landing])
        XCTAssertEqual(stunts.first { $0.kind == .hop }?.count, 5)
        XCTAssertEqual(stunts.first { $0.kind == .hop }?.grade, .greased)
        // Throttle alone takes several seconds to reach 60.
        XCTAssertEqual(stunts.first?.grade, .sketchy)
    }

    func testBackflipIsScoredBeforeTheLanding() {
        let (sim, _) = Pilots.fly { sim in
            let spin = sim.segment == .air && sim.flipRotation < 2 * .pi - 0.5 ? 1 : Pilots.level(sim)
            return Controls(throttle: true, lift: Pilots.liftNearGround(sim), fan: Pilots.fanWindow(sim), spin: spin)
        }
        let kinds = Scorer.stunts(from: sim).map(\.kind)
        XCTAssertEqual(kinds.suffix(2), [.backflip, .landing])
    }

    func testCrashFilesATotaledClaimThatIsAlwaysDenied() {
        let (sim, _) = Pilots.fly(Pilots.throttleOnly)
        let stunts = Scorer.stunts(from: sim)
        XCTAssertEqual(stunts.last?.kind, .totaled)
        XCTAssertEqual(stunts.last?.crash, .fellOffLoop)

        var adjuster = InsuranceAdjuster(seed: 9)
        let report = ClaimsReport(claims: adjuster.fileAll(stunts))
        XCTAssertEqual(report.totaled?.status, .denied(reason: InsuranceAdjuster.noDriverDenial))
        XCTAssertFalse(report.landed)
        XCTAssertEqual(report.score, 0)
    }

    func testRevealBeatingLaunchIsGreased() {
        let (sim, _) = Pilots.fly { sim in
            Controls(
                throttle: true,
                boost: sim.segment == .staging || sim.time < 0.85,
                fan: Pilots.fanWindow(sim),
                spin: Pilots.level(sim)
            )
        }
        let launch = Scorer.stunts(from: sim).first
        XCTAssertEqual(launch?.kind, .launch)
        XCTAssertEqual(launch?.grade, .greased)
        XCTAssertTrue(launch?.detail.contains("0.81") ?? false)
    }

    func testLandingGrades() {
        XCTAssertEqual(Scorer.landingGrade(impact: 1), .greased)
        XCTAssertEqual(Scorer.landingGrade(impact: 5), .clean)
        XCTAssertEqual(Scorer.landingGrade(impact: 8), .sketchy)
    }

    func testReportScoreExcludesTheTotaledClaim() {
        let stunts = [
            Stunt(kind: .launch, grade: .clean, detail: ""),
            Stunt(kind: .loop, grade: .greased, detail: ""),
            Stunt(kind: .totaled, grade: .sketchy, detail: "Landed on the Semi", crash: .hitVehicle("Semi")),
        ]
        var adjuster = InsuranceAdjuster(seed: 4)
        let report = ClaimsReport(claims: adjuster.fileAll(stunts))
        XCTAssertEqual(report.score, report.claims[0].amount + report.claims[1].amount)
        XCTAssertLessThanOrEqual(report.totalPaid, report.score)
        XCTAssertTrue(report.shareText.contains("totaled") || report.shareText.contains("Totaled"))
        XCTAssertEqual(report.rank, CoachRank.forScore(report.score))
    }

    func testClaimAmountsFollowBaseCountAndGrade() {
        var adjuster = InsuranceAdjuster(seed: 42)
        let claim = adjuster.file(Stunt(kind: .hop, grade: .greased, detail: "", count: 5))
        let expected = StuntKind.hop.baseClaim * 5 * Grade.greased.claimMultiplier
        XCTAssertGreaterThanOrEqual(Double(claim.amount), (expected * 0.9).rounded(.down))
        XCTAssertLessThanOrEqual(Double(claim.amount), (expected * 1.15).rounded(.up))
        XCTAssertTrue(claim.id.hasPrefix("RSC-"))
        XCTAssertEqual(claim.id.count, 11)
    }

    func testSameSeedFilesTheSameClaims() {
        let stunts = [Stunt(kind: .launch, grade: .clean, detail: "a"), Stunt(kind: .landing, grade: .greased, detail: "b")]
        var first = InsuranceAdjuster(seed: 7)
        var second = InsuranceAdjuster(seed: 7)
        let a = first.fileAll(stunts)
        let b = second.fileAll(stunts)
        XCTAssertEqual(a, b)
    }

    func testMoneyFormatting() {
        XCTAssertEqual(Money.format(0), "$0")
        XCTAssertEqual(Money.format(999), "$999")
        XCTAssertEqual(Money.format(1_000), "$1,000")
        XCTAssertEqual(Money.format(1_234_567), "$1,234,567")
        XCTAssertEqual(Money.format(-5_000), "-$5,000")
    }

    func testRanks() {
        XCTAssertEqual(CoachRank.forScore(0), .parked)
        XCTAssertEqual(CoachRank.forScore(19_999), .learnersPermit)
        XCTAssertEqual(CoachRank.forScore(20_000), .weekendStuntDriver)
        XCTAssertEqual(CoachRank.forScore(94_999), .closedCoursePro)
        XCTAssertEqual(CoachRank.forScore(95_000), .uninsurable)
    }
}

final class SteeringAndCoachTests: XCTestCase {
    func testTurningThePhoneClockwiseReadsPositive() {
        // Landscape, held level: gravity points along -x. Turning the phone clockwise by 10°
        // turns gravity counterclockwise by 10° in the phone's own frame.
        let angle = 10 * Double.pi / 180
        let wheel = TiltSteering.wheelAngle(reference: (x: -1, y: 0), current: (x: -cos(angle), y: -sin(angle)))
        XCTAssertEqual(wheel, 10, accuracy: 1e-9)
    }

    func testFlatPhoneDoesNotSteer() {
        XCTAssertEqual(TiltSteering.wheelAngle(reference: (x: 0, y: 0.05), current: (x: 0.05, y: 0)), 0)
    }

    func testSpinHasADeadZoneAndFullLock() {
        XCTAssertEqual(TiltSteering.spin(wheelAngleDegrees: 3), 0)
        XCTAssertEqual(TiltSteering.spin(wheelAngleDegrees: 40), -1)
        XCTAssertEqual(TiltSteering.spin(wheelAngleDegrees: -40), 1)
        XCTAssertEqual(TiltSteering.spin(wheelAngleDegrees: 17), -0.5, accuracy: 1e-9)
    }

    func testCoachCallsForTheFanBeforeTheLoop() {
        XCTAssertTrue(Coach.line(for: LaunchSim()).contains("THROTTLE"))
        var sim = LaunchSim()
        while sim.segment != .loop && sim.x < sim.course.loopX - 6 {
            sim.step(1.0 / 120.0, controls: Controls(throttle: true))
        }
        XCTAssertEqual(Coach.line(for: sim), "Loop ahead! FAN ON or BOOST!")
    }
}
