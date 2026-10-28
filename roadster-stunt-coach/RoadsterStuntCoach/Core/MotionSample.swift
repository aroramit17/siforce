import Foundation

/// A reading on the device's three axes: x points to the right edge of the screen,
/// y to the top edge, and z out of the screen toward your face.
struct Vector3: Equatable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vector3(x: 0, y: 0, z: 0)

    var magnitude: Double { (x * x + y * y + z * z).squareRoot() }

    func dot(_ other: Vector3) -> Double { x * other.x + y * other.y + z * other.z }

    static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func * (lhs: Vector3, rhs: Double) -> Vector3 {
        Vector3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }
}

/// The parts of `CMDeviceMotion` the coach cares about. Kept free of CoreMotion so the
/// detector can be tested with scripted motion instead of a real phone.
struct MotionSample {
    /// Seconds on the same clock as `ProcessInfo.systemUptime` (what CMDeviceMotion uses).
    var time: TimeInterval
    /// Radians per second around each device axis.
    var rotationRate: Vector3
    /// Gravity in g, pointing at the ground.
    var gravity: Vector3
    /// Acceleration the player applied, in g, with gravity removed.
    var userAcceleration: Vector3
}
