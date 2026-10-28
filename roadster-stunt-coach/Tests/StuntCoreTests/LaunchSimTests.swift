import XCTest
@testable import StuntCore

final class LaunchSimTests: XCTestCase {
    // MARK: - The loop

    func testThrottleAloneFallsOffTheCeiling() {
        let (sim, events) = Pilots.fly(Pilots.throttleOnly)
        XCTAssertTrue(events.contains(.fellOffLoop))
        XCTAssertFalse(sim.loopCompleted)
        XCTAssertEqual(sim.crashReason, .fellOffLoop)
        XCTAssertFalse(sim.landed)
    }

    func testFanThroughTheLoopLandsTheWholeCourse() {
        let (sim, events) = Pilots.fly(Pilots.fanThroughTheLoop)
        XCTAssertTrue(sim.loopCompleted)
        XCTAssertEqual(sim.clearedCount, 5)
        XCTAssertTrue(sim.landed)
        XCTAssertNil(sim.crashReason)
        XCTAssertLessThan(sim.landingImpact ?? .infinity, 9)
        XCTAssertTrue(events.contains(.completedLoop))
        XCTAssertEqual(events.filter { if case .cleared = $0 { return true } else { return false } }.count, 5)
        XCTAssertEqual(events.last, .finished)
    }

    func testBoostingInsteadOfTheFanAlsoMakesIt() {
        let (sim, _) = Pilots.fly { sim in
            Controls(throttle: true, boost: sim.segment == .staging || sim.time < 0.6, spin: Pilots.level(sim))
        }
        XCTAssertTrue(sim.loopCompleted)
        XCTAssertTrue(sim.landed)
        XCTAssertEqual(sim.air, 0.85, accuracy: 0.01)
    }

    func testFanLeftOnOverheatsAndDropsTheCar() {
        let (sim, events) = Pilots.fly { sim in
            Controls(throttle: true, fan: true, spin: Pilots.level(sim))
        }
        XCTAssertEqual(events.filter { $0 == .fanOverheated }.count, 1)
        XCTAssertEqual(sim.crashReason, .fellOffLoop)
    }

    // MARK: - Launch

    func testNothingMovesUntilThrottleOrBoost() {
        var sim = LaunchSim()
        for _ in 0..<240 { sim.step(1.0 / 120.0, controls: Controls(fan: false)) }
        XCTAssertEqual(sim.segment, .staging)
        XCTAssertEqual(sim.time, 0)
        XCTAssertEqual(sim.x, 0)
    }

    func testFullBoostFromTheLineBeatsTheRevealTime() {
        let (sim, _) = Pilots.fly { sim in
            Controls(
                throttle: true,
                boost: sim.segment == .staging || sim.time < 0.85,
                fan: Pilots.fanWindow(sim),
                spin: Pilots.level(sim)
            )
        }
        XCTAssertLessThan(sim.sixtyTime ?? .infinity, Scorer.revealSixtyTime)
        XCTAssertTrue(sim.landed)
    }

    // MARK: - Fan and air

    func testFanSpoolsUpInHalfASecond() {
        var sim = LaunchSim()
        for _ in 0..<60 { sim.step(1.0 / 120.0, controls: Controls(fan: true)) }
        XCTAssertEqual(sim.fanRPM, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(sim.fanTemperature, 0)
    }

    func testFanLocksOutWhenItOverheats() {
        var sim = LaunchSim()
        for _ in 0..<(120 * 5) { sim.step(1.0 / 120.0, controls: Controls(fan: true)) }
        XCTAssertTrue(sim.fanLocked)
        let events = sim.drainEvents()
        XCTAssertEqual(events, [.fanOverheated])
    }

    func testBoostBurnsAQuarterTankASecond() {
        var sim = LaunchSim()
        for _ in 0..<120 { sim.step(1.0 / 120.0, controls: Controls(throttle: true, boost: true)) }
        XCTAssertEqual(sim.air, 0.75, accuracy: 1e-6)
    }

    func testRunningTheTanksDryIsAnnouncedOnceAndLandsHard() {
        let (sim, events) = Pilots.fly { sim in
            Controls(throttle: true, boost: true, spin: Pilots.level(sim))
        }
        XCTAssertEqual(sim.air, 0)
        XCTAssertEqual(events.filter { $0 == .outOfAir }.count, 1)
        XCTAssertEqual(sim.crashReason, .hardLanding)
    }

    // MARK: - Air and landing

    func testLandingNoseUpIsTheWrongAngle() {
        let (sim, _) = Pilots.fly { sim in
            Controls(throttle: true, fan: Pilots.fanWindow(sim))
        }
        XCTAssertEqual(sim.clearedCount, 5)
        XCTAssertEqual(sim.crashReason, .wrongAngle)
    }

    func testCoastingFromTheTopOfTheLoopComesUpShortOnTheSemi() {
        let (sim, _) = Pilots.fly { sim in
            let throttle = sim.segment == .staging || sim.segment == .runway || (sim.segment == .loop && sim.angle < 3)
            return Controls(throttle: throttle, fan: Pilots.fanWindow(sim), spin: Pilots.level(sim))
        }
        XCTAssertTrue(sim.loopCompleted)
        XCTAssertEqual(sim.clearedCount, 4)
        XCTAssertEqual(sim.crashReason, .hitVehicle("Semi"))
    }

    func testBackflipWithALiftBurnLands() {
        let (sim, _) = Pilots.fly { sim in
            let spin = sim.segment == .air && sim.flipRotation < 2 * .pi - 0.5 ? 1 : Pilots.level(sim)
            return Controls(throttle: true, lift: Pilots.liftNearGround(sim), fan: Pilots.fanWindow(sim), spin: spin)
        }
        XCTAssertTrue(sim.landed)
        XCTAssertEqual(sim.flips, 1)
        XCTAssertLessThan(sim.air, 1)
    }

    // MARK: - Course

    func testLandingRampProfile() {
        let course = Course()
        XCTAssertEqual(course.ground(at: course.rampTop - 0.01).height, 0)
        XCTAssertEqual(course.ground(at: course.rampTop).height, 7, accuracy: 1e-9)
        XCTAssertEqual(course.ground(at: course.rampBottom).height, 0, accuracy: 1e-9)
        XCTAssertEqual(course.ground(at: course.rampTop + 1).slope, -12 * .pi / 180, accuracy: 1e-9)
        XCTAssertGreaterThan(course.rampTop, course.vehicles.last?.x1 ?? .infinity)
    }

    func testVehiclesSitBetweenTheKickerAndTheLandingRamp() {
        let course = Course()
        XCTAssertEqual(course.vehicles.map(\.name), ["Sedan", "Crossover", "Angular Truck", "Robotaxi", "Semi"])
        for (left, right) in zip(course.vehicles, course.vehicles.dropFirst()) {
            XCTAssertLessThan(left.x1, right.x0)
        }
        XCTAssertGreaterThan(course.vehicles[0].x0, course.lipX)
    }
}
