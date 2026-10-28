import XCTest
@testable import StuntCore

final class StuntDetectorTests: XCTestCase {
    private func run(_ build: (inout MotionScript) -> Void) -> [DetectedStunt] {
        var script = MotionScript()
        script.rest(0.1)
        build(&script)
        script.rest(0.3)
        return script.detect()
    }

    // MARK: - Flips

    func testKickflip() {
        let stunts = run { $0.rotate(y: 360, over: 0.5) }
        XCTAssertEqual(stunts.map(\.kind), [.kickflip])
        XCTAssertEqual(stunts.first?.landing, .greased)
        XCTAssertEqual(stunts.first?.degrees ?? 0, 360, accuracy: 1)
    }

    func testKickflipInTheOtherDirection() {
        XCTAssertEqual(run { $0.rotate(y: -360, over: 0.5) }.map(\.kind), [.kickflip])
    }

    func testDoubleKickflip() {
        XCTAssertEqual(run { $0.rotate(y: 720, over: 0.8) }.map(\.kind), [.doubleKickflip])
    }

    func testTreFlipIsAKickflipWithASpin() {
        XCTAssertEqual(run { $0.rotate(y: 360, z: 180, over: 0.5) }.map(\.kind), [.treFlip])
    }

    func testBackflip() {
        XCTAssertEqual(run { $0.rotate(x: 360, over: 0.5) }.map(\.kind), [.backflip])
    }

    func testDonut() {
        XCTAssertEqual(run { $0.rotate(z: 360, over: 0.6) }.map(\.kind), [.donut])
    }

    func testUnderRotatedKickflipLandsSketchy() {
        let stunts = run {
            $0.rotate(y: 330, over: 0.5)
            $0.rotate(y: -100, over: 0.2)
        }
        XCTAssertEqual(stunts.map(\.kind), [.kickflip])
        XCTAssertEqual(stunts.first?.landing, .sketchy)
    }

    func testFlipLandingGrades() {
        XCTAssertEqual(StuntDetector.flipLanding(netDegrees: 350), .greased)
        XCTAssertEqual(StuntDetector.flipLanding(netDegrees: -365), .greased)
        XCTAssertEqual(StuntDetector.flipLanding(netDegrees: 700), .greased)
        XCTAssertEqual(StuntDetector.flipLanding(netDegrees: 410), .clean)
        XCTAssertEqual(StuntDetector.flipLanding(netDegrees: 180), .sketchy)
    }

    // MARK: - Ramp

    func testRampUpAndBackDown() {
        let stunts = run {
            $0.rotate(x: 60, over: 0.25)
            $0.rotate(x: -60, over: 0.25)
        }
        XCTAssertEqual(stunts.map(\.kind), [.ramp])
        XCTAssertEqual(stunts.first?.landing, .clean)
        XCTAssertEqual(stunts.first?.degrees ?? 0, 60, accuracy: 1)
    }

    func testBigRampThatComesAllTheWayDownIsGreased() {
        let stunts = run {
            $0.rotate(x: 85, over: 0.25)
            $0.rotate(x: -85, over: 0.25)
        }
        XCTAssertEqual(stunts.first?.landing, .greased)
    }

    func testPausingAtTheTopOfARampCountsOnce() {
        let stunts = run {
            $0.rotate(x: 60, over: 0.25)
            $0.rest(0.3)
            $0.rotate(x: -60, over: 0.25)
        }
        XCTAssertEqual(stunts.map(\.kind), [.ramp])
        XCTAssertEqual(stunts.first?.landing, .sketchy)
    }

    func testTwoSeparateRampsBothCount() {
        let stunts = run {
            $0.rotate(x: 60, over: 0.25)
            $0.rotate(x: -60, over: 0.25)
            $0.rest(0.5)
            $0.rotate(x: 60, over: 0.25)
            $0.rotate(x: -60, over: 0.25)
        }
        XCTAssertEqual(stunts.map(\.kind), [.ramp, .ramp])
    }

    // MARK: - Things that aren't stunts

    func testSmallWobbleIsIgnored() {
        let stunts = run {
            $0.rotate(x: 20, over: 0.1)
            $0.rotate(x: -20, over: 0.1)
        }
        XCTAssertEqual(stunts, [])
    }

    func testSlowTiltIsIgnored() {
        XCTAssertEqual(run { $0.rotate(x: 90, over: 2) }, [])
    }

    func testStalledSensorCannotFakeAFlip() {
        let gravity = Vector3(x: 0, y: -1, z: 0)
        let spin = Vector3(x: 0, y: 8, z: 0)
        var detector = StuntDetector()
        var stunts: [DetectedStunt] = []
        stunts += detector.process(MotionSample(time: 0, rotationRate: .zero, gravity: gravity, userAcceleration: .zero))
        // A full second with no samples, then one fast reading: at most 50 ms of it counts.
        stunts += detector.process(MotionSample(time: 1, rotationRate: spin, gravity: gravity, userAcceleration: .zero))
        for step in 1...30 {
            let sample = MotionSample(time: 1 + Double(step) * 0.01, rotationRate: .zero, gravity: gravity, userAcceleration: .zero)
            stunts += detector.process(sample)
        }
        XCTAssertEqual(stunts, [])
    }

    // MARK: - Launch

    func testLaunch() {
        XCTAssertEqual(run { $0.jolt(up: 1.3, over: 0.05) }.map(\.kind), [.launch])
    }

    func testDownwardJoltIsNotALaunch() {
        XCTAssertEqual(run { $0.jolt(up: -1.5, over: 0.05) }, [])
    }

    func testLaunchCooldown() {
        let quick = run {
            $0.jolt(up: 1.3, over: 0.05)
            $0.rest(0.2)
            $0.jolt(up: 1.3, over: 0.05)
        }
        XCTAssertEqual(quick.map(\.kind), [.launch])

        let spaced = run {
            $0.jolt(up: 1.3, over: 0.05)
            $0.rest(0.7)
            $0.jolt(up: 1.3, over: 0.05)
        }
        XCTAssertEqual(spaced.map(\.kind), [.launch, .launch])
    }

    func testLaunchWorksWithThePhoneLyingFlat() {
        var script = MotionScript()
        script.gravity = Vector3(x: 0, y: 0, z: -1)
        script.rest(0.1)
        script.jolt(up: 1.3, over: 0.05)
        XCTAssertEqual(script.detect().map(\.kind), [.launch])
    }

    // MARK: - Hover

    func testHoldingStillForASecondIsAHover() {
        XCTAssertEqual(run { $0.rest(1.0) }.map(\.kind), [.hover])
    }

    func testOneHoverPerStillness() {
        XCTAssertEqual(run { $0.rest(3) }.map(\.kind), [.hover])
    }

    func testMovingRearmsTheHover() {
        let stunts = run {
            $0.rest(1.1)
            $0.rotate(x: 10, over: 0.5)
            $0.rest(1.1)
        }
        XCTAssertEqual(stunts.map(\.kind), [.hover, .hover])
    }
}
