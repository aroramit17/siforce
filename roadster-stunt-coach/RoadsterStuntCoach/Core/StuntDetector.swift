import Foundation

/// Turns a stream of motion samples into stunts.
///
/// Rotation stunts are found by splitting motion into gestures: a gesture starts when the
/// phone spins faster than `gestureStartRate`, integrates rotation on each axis, and ends
/// once the phone has settled below `gestureEndRate` for `settleDuration`. The finished
/// gesture is classified by how far it got on each axis (its peak) and graded by where it
/// ended up (its net rotation). Launches and hovers are checked on every sample.
struct StuntDetector {
    struct Thresholds {
        /// Radians per second (about 145°/s) needed to start a rotation gesture.
        var gestureStartRate = 2.5
        /// Below this the phone counts as settling.
        var gestureEndRate = 1.0
        var settleDuration: TimeInterval = 0.15
        var maxGestureDuration: TimeInterval = 2.0

        var rampMinDegrees = 40.0
        var flipMinDegrees = 300.0
        var doubleFlipMinDegrees = 660.0
        var treSpinMinDegrees = 150.0
        /// A ramp in the opposite direction this soon after a ramp is just the way back down.
        var rampDescentWindow: TimeInterval = 0.8

        /// Upward acceleration, in g, for a launch.
        var launchMinG = 1.1
        var launchCooldown: TimeInterval = 0.6

        var hoverDuration: TimeInterval = 1.0
        var hoverMaxRate = 0.25
        var hoverMaxG = 0.06
    }

    private struct Gesture {
        var start: TimeInterval
        /// Signed rotation so far, in radians.
        var net = Vector3.zero
        /// The furthest `net` reached on each axis, keeping its sign.
        var peak = Vector3.zero
        var settlingSince: TimeInterval?
    }

    var thresholds: Thresholds

    private var lastTime: TimeInterval?
    private var gesture: Gesture?
    private var lastRamp: (time: TimeInterval, sign: Double)?
    private var lastLaunch: TimeInterval = -.infinity
    private var stillSince: TimeInterval?
    private var hoverArmed = true

    init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    mutating func process(_ sample: MotionSample) -> [DetectedStunt] {
        // Clamp the step so a stalled sensor can't turn into a phantom 720.
        let dt = lastTime.map { min(max(sample.time - $0, 0), 0.05) } ?? 0
        lastTime = sample.time

        var stunts: [DetectedStunt] = []
        if let stunt = trackRotation(sample, dt: dt) { stunts.append(stunt) }
        if let stunt = trackLaunch(sample) { stunts.append(stunt) }
        if let stunt = trackHover(sample) { stunts.append(stunt) }
        return stunts
    }

    // MARK: - Rotation

    private mutating func trackRotation(_ sample: MotionSample, dt: TimeInterval) -> DetectedStunt? {
        let rate = sample.rotationRate.magnitude
        if gesture == nil {
            guard rate >= thresholds.gestureStartRate else { return nil }
            gesture = Gesture(start: sample.time)
        }
        guard var current = gesture else { return nil }

        current.net = current.net + sample.rotationRate * dt
        current.peak = Vector3(
            x: furthest(current.peak.x, current.net.x),
            y: furthest(current.peak.y, current.net.y),
            z: furthest(current.peak.z, current.net.z)
        )

        if rate < thresholds.gestureEndRate {
            if current.settlingSince == nil { current.settlingSince = sample.time }
        } else {
            current.settlingSince = nil
        }

        let settled = current.settlingSince.map { sample.time - $0 >= thresholds.settleDuration } ?? false
        let timedOut = sample.time - current.start >= thresholds.maxGestureDuration
        guard settled || timedOut else {
            gesture = current
            return nil
        }
        gesture = nil
        return classify(current, at: sample.time)
    }

    private mutating func classify(_ finished: Gesture, at time: TimeInterval) -> DetectedStunt? {
        let peak = finished.peak * (180 / Double.pi)
        let net = finished.net * (180 / Double.pi)
        let px = abs(peak.x), py = abs(peak.y), pz = abs(peak.z)
        let t = thresholds

        func flip(_ kind: StuntKind, peak: Double, net: Double) -> DetectedStunt {
            DetectedStunt(kind: kind, time: time, landing: Self.flipLanding(netDegrees: net), degrees: peak)
        }

        if py >= t.flipMinDegrees && pz >= t.treSpinMinDegrees { return flip(.treFlip, peak: py, net: net.y) }
        if py >= t.doubleFlipMinDegrees { return flip(.doubleKickflip, peak: py, net: net.y) }
        if py >= t.flipMinDegrees { return flip(.kickflip, peak: py, net: net.y) }
        if px >= t.flipMinDegrees { return flip(.backflip, peak: px, net: net.x) }
        if pz >= t.flipMinDegrees { return flip(.donut, peak: pz, net: net.z) }

        guard px >= t.rampMinDegrees, px > py, px > pz else { return nil }
        let sign: Double = peak.x < 0 ? -1 : 1
        if let last = lastRamp, last.sign != sign, time - last.time <= t.rampDescentWindow {
            lastRamp = nil
            return nil
        }
        lastRamp = (time, sign)
        return DetectedStunt(
            kind: .ramp,
            time: time,
            landing: Self.rampLanding(peakDegrees: px, netDegrees: abs(net.x)),
            degrees: px
        )
    }

    /// How close the flip came to landing wheels-down (a whole number of turns).
    static func flipLanding(netDegrees: Double) -> LandingGrade {
        let leftover = abs(netDegrees).truncatingRemainder(dividingBy: 360)
        let miss = min(leftover, 360 - leftover)
        if miss <= 25 { return .greased }
        if miss <= 60 { return .clean }
        return .sketchy
    }

    /// A ramp lands when the nose comes back down. Big air that comes all the way down is greased.
    static func rampLanding(peakDegrees: Double, netDegrees: Double) -> LandingGrade {
        if netDegrees <= 15 && peakDegrees >= 70 { return .greased }
        if netDegrees <= 30 { return .clean }
        return .sketchy
    }

    private func furthest(_ current: Double, _ candidate: Double) -> Double {
        abs(candidate) > abs(current) ? candidate : current
    }

    // MARK: - Launch and hover

    private mutating func trackLaunch(_ sample: MotionSample) -> DetectedStunt? {
        let g = sample.gravity.magnitude
        guard g > 0.1 else { return nil }
        // Gravity points down, so upward acceleration is the part opposite to it.
        let up = -sample.userAcceleration.dot(sample.gravity) / g
        guard up >= thresholds.launchMinG, sample.time - lastLaunch >= thresholds.launchCooldown else { return nil }
        lastLaunch = sample.time
        return DetectedStunt(kind: .launch, time: sample.time, landing: .clean, degrees: 0)
    }

    private mutating func trackHover(_ sample: MotionSample) -> DetectedStunt? {
        let still = gesture == nil
            && sample.rotationRate.magnitude <= thresholds.hoverMaxRate
            && sample.userAcceleration.magnitude <= thresholds.hoverMaxG
        guard still else {
            stillSince = nil
            hoverArmed = true
            return nil
        }
        let since = stillSince ?? sample.time
        stillSince = since
        guard hoverArmed, sample.time - since >= thresholds.hoverDuration else { return nil }
        // One hover per stillness; the player has to move before hovering again.
        hoverArmed = false
        return DetectedStunt(kind: .hover, time: sample.time, landing: .clean, degrees: 0)
    }
}
