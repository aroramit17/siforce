import CoreMotion
import Foundation

/// Streams device motion at 100 Hz on the main queue. Device motion fuses the gyro and
/// accelerometer and needs no permission prompt.
final class MotionEngine {
    private let manager = CMMotionManager()

    /// False in the Simulator, which has no gyro. The run screen shows stunt buttons instead.
    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start(onSample: @escaping @MainActor (MotionSample) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 100.0
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let motion else { return }
            let sample = MotionSample(
                time: motion.timestamp,
                rotationRate: Vector3(x: motion.rotationRate.x, y: motion.rotationRate.y, z: motion.rotationRate.z),
                gravity: Vector3(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z),
                userAcceleration: Vector3(
                    x: motion.userAcceleration.x,
                    y: motion.userAcceleration.y,
                    z: motion.userAcceleration.z
                )
            )
            MainActor.assumeIsolated { onSample(sample) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
