@testable import StuntCore

/// Scripted drivers for the course: each looks at the sim and decides what to press.
enum Pilots {
    typealias Pilot = (LaunchSim) -> Controls

    /// Flies the course at 120 Hz until the run ends or `seconds` pass.
    static func fly(maxSeconds seconds: Double = 40, _ pilot: Pilot) -> (sim: LaunchSim, events: [SimEvent]) {
        var sim = LaunchSim()
        var events: [SimEvent] = []
        let dt = 1.0 / 120.0
        var steps = 0
        while !sim.isOver && Double(steps) * dt < seconds {
            sim.step(dt, controls: pilot(sim))
            events += sim.drainEvents()
            steps += 1
        }
        return (sim, events)
    }

    /// In the air, rotate toward `degrees` of pitch (the landing ramp is -12°).
    static func level(_ sim: LaunchSim, to degrees: Double = -12) -> Double {
        guard sim.segment == .air else { return 0 }
        return max(-1, min(1, (degrees * .pi / 180 - sim.angle) * 3))
    }

    /// Fan on from 10 m before the loop until 40 m into it (past the upside-down top at 44 m).
    static func fanWindow(_ sim: LaunchSim) -> Bool {
        switch sim.segment {
        case .runway: return sim.x > sim.course.loopX - 10
        case .loop: return sim.angle < 40 / sim.course.loopRadius
        default: return false
        }
    }

    static func liftNearGround(_ sim: LaunchSim) -> Bool {
        sim.segment == .air && sim.vy < -6 && sim.y < 9
    }

    static let throttleOnly: Pilot = { sim in
        Controls(throttle: true, spin: Pilots.level(sim))
    }

    static let fanThroughTheLoop: Pilot = { sim in
        Controls(throttle: true, fan: Pilots.fanWindow(sim), spin: Pilots.level(sim))
    }
}
