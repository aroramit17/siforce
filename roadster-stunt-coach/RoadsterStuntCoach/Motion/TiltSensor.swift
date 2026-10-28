import CoreMotion
import Foundation

/// Reads the phone's tilt for steering the car in the air. Polls device motion
/// instead of taking callbacks, since the game loop asks for it once a frame anyway.
/// Device motion needs no permission prompt.
final class TiltSensor {
    private let manager = CMMotionManager()
    private var reference: (x: Double, y: Double)?

    /// False in the Simulator, which has no gyro. The cockpit shows rotate buttons instead.
    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates()
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    /// Treat however the phone is held right now as "wheel straight".
    func recenter() {
        reference = nil
    }

    /// Degrees turned like a steering wheel since `recenter()`, clockwise positive.
    var wheelAngle: Double {
        guard let gravity = manager.deviceMotion?.gravity else { return 0 }
        let current = (x: gravity.x, y: gravity.y)
        guard let reference else {
            reference = current
            return 0
        }
        return TiltSteering.wheelAngle(reference: reference, current: current)
    }
}
