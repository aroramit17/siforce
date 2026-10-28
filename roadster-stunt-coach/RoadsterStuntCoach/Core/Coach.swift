import Foundation

/// Phone-as-steering-wheel attitude control for the car in the air.
enum TiltSteering {
    static let deadZoneDegrees = 4.0
    static let fullLockDegrees = 30.0

    /// How far the phone has turned, like a steering wheel, since `reference` was captured.
    /// Takes gravity's x and y in device coordinates, so it works in any orientation.
    /// Clockwise (as you look at the screen) is positive.
    static func wheelAngle(reference: (x: Double, y: Double), current: (x: Double, y: Double)) -> Double {
        let referenceLength = (reference.x * reference.x + reference.y * reference.y).squareRoot()
        let currentLength = (current.x * current.x + current.y * current.y).squareRoot()
        // Lying flat, gravity has no direction on the screen to steer by.
        guard referenceLength > 0.3, currentLength > 0.3 else { return 0 }
        let cross = reference.x * current.y - reference.y * current.x
        let dot = reference.x * current.x + reference.y * current.y
        return atan2(cross, dot) * 180 / .pi
    }

    /// Turning the phone clockwise rotates the car clockwise (nose down), and vice versa.
    static func spin(wheelAngleDegrees angle: Double) -> Double {
        let magnitude = abs(angle)
        guard magnitude > deadZoneDegrees else { return 0 }
        let amount = min(1, (magnitude - deadZoneDegrees) / (fullLockDegrees - deadZoneDegrees))
        return angle > 0 ? -amount : amount
    }
}

/// The coach shouting from the pit wall, based on what the car is doing right now.
enum Coach {
    static func line(for sim: LaunchSim) -> String {
        if sim.fanLocked && sim.segment != .done && sim.segment != .crashed {
            return "Fan overheated! Let it cool!"
        }
        switch sim.segment {
        case .staging:
            return "Hold THROTTLE to launch. Arm the FAN before the loop."
        case .runway:
            let toLoop = sim.course.loopX - sim.x
            if toLoop < 12 && sim.fanRPM < 0.5 { return "Loop ahead! FAN ON or BOOST!" }
            if sim.sixtyTime == nil && sim.boostFiring { return "Boosters lit! Chase that 0.81!" }
            return "Build speed!"
        case .loop:
            if let grip = sim.gripG, grip < 0.4 { return "GRIP LOW! More fan, more speed!" }
            if sim.isInverted { return "You're on the ceiling! Hold it!" }
            return "Into the loop!"
        case .flat:
            return sim.fanRPM > 0.5 ? "Loop done. Fan OFF, save the heat." : "Line up the kicker. Full throttle!"
        case .kicker:
            return "SEND IT!"
        case .air:
            let slopeDegrees = sim.course.rampSlope * 180 / .pi
            var tilt = (sim.angle * 180 / .pi - slopeDegrees).truncatingRemainder(dividingBy: 360)
            if tilt > 180 { tilt -= 360 }
            if tilt < -180 { tilt += 360 }
            if sim.vy < -6 && sim.altitude < 8 && !sim.liftFiring && sim.air > 0 { return "LIFT! Soften the landing!" }
            if tilt > 20 { return "Nose down! Tilt to match the ramp!" }
            if tilt < -20 { return "Nose up! Tilt back!" }
            return "Clear the lineup!"
        case .rollout:
            return "STUCK IT!"
        case .crashed, .done:
            return sim.landed ? "That's how you launch a car." : "Well. That's a claim."
        }
    }
}
