import XCTest
@testable import StuntCore

final class FuelGaugeTests: XCTestCase {
    func testBurnsFourSecondsInRealTime() {
        var fuel = FuelGauge()
        fuel.burn(to: 10)
        XCTAssertEqual(fuel.remaining, 4, accuracy: 1e-9)
        fuel.burn(to: 12)
        XCTAssertEqual(fuel.remaining, 2, accuracy: 1e-9)
        XCTAssertEqual(fuel.fraction, 0.5, accuracy: 1e-9)
        fuel.burn(to: 20)
        XCTAssertEqual(fuel.remaining, 0)
        XCTAssertTrue(fuel.isEmpty)
    }

    func testIgnoresTimeGoingBackwards() {
        var fuel = FuelGauge()
        fuel.burn(to: 10)
        fuel.burn(to: 11)
        fuel.burn(to: 10.5)
        XCTAssertEqual(fuel.remaining, 3, accuracy: 1e-9)
        fuel.burn(to: 12)
        XCTAssertEqual(fuel.remaining, 2, accuracy: 1e-9)
    }

    func testRefundIsCappedAtAFullTank() {
        var fuel = FuelGauge()
        fuel.burn(to: 10)
        fuel.burn(to: 10.1)
        fuel.refund(0.3)
        XCTAssertEqual(fuel.remaining, FuelGauge.capacity)
    }

    func testEmptyTankStaysEmpty() {
        var fuel = FuelGauge()
        fuel.burn(to: 0)
        fuel.burn(to: 5)
        fuel.refund(1)
        XCTAssertTrue(fuel.isEmpty)
    }
}

final class GameSessionTests: XCTestCase {
    private func stunt(_ kind: StuntKind, at time: Double, landing: LandingGrade = .clean) -> DetectedStunt {
        DetectedStunt(kind: kind, time: time, landing: landing, degrees: 0)
    }

    func testStuntsCloseTogetherBuildAChain() {
        var session = GameSession(seed: 1)
        session.start(at: 0)
        XCTAssertEqual(session.land(stunt(.ramp, at: 0.5)).chain, 1)
        XCTAssertEqual(session.land(stunt(.ramp, at: 1.5)).chain, 2)
        let third = session.land(stunt(.ramp, at: 2.5))
        XCTAssertEqual(third.chain, 3)
        XCTAssertEqual(third.multiplier, 1.5, accuracy: 1e-9)
        XCTAssertEqual(session.land(stunt(.ramp, at: 5)).chain, 1)
        XCTAssertEqual(session.bestChain, 3)
    }

    func testMultiplierIsCapped() {
        XCTAssertEqual(GameSession.multiplier(forChain: 1), 1)
        XCTAssertEqual(GameSession.multiplier(forChain: 5), 2)
        XCTAssertEqual(GameSession.multiplier(forChain: 50), GameSession.maxMultiplier)
    }

    func testCleanLandingsRefundFuelButHoversDoNot() {
        var session = GameSession(seed: 1)
        session.start(at: 0)
        session.tick(to: 1)
        session.land(stunt(.kickflip, at: 1, landing: .greased))
        XCTAssertEqual(session.fuel.remaining, 3.3, accuracy: 1e-9)
        session.land(stunt(.hover, at: 1, landing: .clean))
        XCTAssertEqual(session.fuel.remaining, 3.3, accuracy: 1e-9)
    }

    func testClaimAmountFollowsBaseLandingAndJitter() {
        var session = GameSession(seed: 42)
        session.start(at: 0)
        let claim = session.land(stunt(.kickflip, at: 0.5, landing: .greased))
        let expected = StuntKind.kickflip.baseClaim * LandingGrade.greased.claimMultiplier
        XCTAssertGreaterThanOrEqual(Double(claim.amount), (expected * 0.9).rounded(.down))
        XCTAssertLessThanOrEqual(Double(claim.amount), (expected * 1.15).rounded(.up))
        XCTAssertTrue(claim.id.hasPrefix("RSC-"))
        XCTAssertEqual(claim.id.count, 11)
        XCTAssertFalse(claim.description.isEmpty)
        XCTAssertFalse(claim.adjusterNote.isEmpty)
    }

    func testSameSeedFilesTheSameClaims() {
        func play() -> [InsuranceClaim] {
            var session = GameSession(seed: 7)
            session.start(at: 0)
            session.land(stunt(.ramp, at: 0.2))
            session.land(stunt(.kickflip, at: 0.9, landing: .greased))
            session.land(stunt(.donut, at: 3, landing: .sketchy))
            return session.claims
        }
        XCTAssertEqual(play(), play())
    }

    func testMotionBecomesClaims() {
        var script = MotionScript()
        script.rest(0.1)
        script.rotate(y: 360, over: 0.5)
        script.rest(0.3)

        var session = GameSession(seed: 3)
        session.start(at: 0)
        var filed: [InsuranceClaim] = []
        for sample in script.samples {
            filed += session.ingest(sample)
        }
        XCTAssertEqual(filed.map(\.stunt.kind), [.kickflip])
        XCTAssertEqual(session.claims, filed)
    }

    func testNoClaimsAfterTheTankRunsDry() {
        var script = MotionScript()
        script.rest(0.1)
        script.rotate(y: 360, over: 0.5)
        script.rest(0.3)

        var session = GameSession(seed: 3)
        session.start(at: 0)
        session.tick(to: 4)
        XCTAssertTrue(session.isOver)
        for sample in script.samples {
            let filed = session.ingest(sample)
            XCTAssertEqual(filed, [])
        }
    }
}

final class ClaimsReportTests: XCTestCase {
    func testMoneyFormatting() {
        XCTAssertEqual(Money.format(0), "$0")
        XCTAssertEqual(Money.format(999), "$999")
        XCTAssertEqual(Money.format(1_000), "$1,000")
        XCTAssertEqual(Money.format(1_234_567), "$1,234,567")
        XCTAssertEqual(Money.format(-5_000), "-$5,000")
    }

    func testRanks() {
        XCTAssertEqual(CoachRank.forTotal(0), .parked)
        XCTAssertEqual(CoachRank.forTotal(1), .learnersPermit)
        XCTAssertEqual(CoachRank.forTotal(14_999), .learnersPermit)
        XCTAssertEqual(CoachRank.forTotal(15_000), .weekendStuntDriver)
        XCTAssertEqual(CoachRank.forTotal(99_999), .closedCoursePro)
        XCTAssertEqual(CoachRank.forTotal(100_000), .uninsurable)
    }

    func testReportTotals() {
        var session = GameSession(seed: 11)
        session.start(at: 0)
        for (index, kind) in StuntKind.allCases.enumerated() {
            session.land(DetectedStunt(kind: kind, time: Double(index) * 0.5, landing: .clean, degrees: 0))
        }
        let report = session.report()
        XCTAssertEqual(report.claims.count, StuntKind.allCases.count)
        XCTAssertEqual(report.totalClaimed, session.totalClaimed)
        XCTAssertLessThanOrEqual(report.totalPaid, report.totalClaimed)
        XCTAssertEqual(report.bestChain, StuntKind.allCases.count)
        XCTAssertTrue(report.shareText.contains(Money.format(report.totalClaimed)))
        XCTAssertEqual(report.rank, CoachRank.forTotal(report.totalClaimed))
    }

    func testEmptyReport() {
        let report = GameSession(seed: 1).report()
        XCTAssertEqual(report.totalClaimed, 0)
        XCTAssertEqual(report.rank, .parked)
        XCTAssertTrue(report.shareText.contains("zero"))
    }
}
