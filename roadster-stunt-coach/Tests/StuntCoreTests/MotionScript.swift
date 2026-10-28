@testable import StuntCore

/// Builds 100 Hz motion the way a player would produce it, one segment at a time.
struct MotionScript {
    static let hz = 100.0

    private(set) var samples: [MotionSample] = []
    private var time: Double = 0

    /// Phone held upright in portrait: gravity runs down the y axis.
    var gravity = Vector3(x: 0, y: -1, z: 0)

    /// Holds still for `seconds`.
    mutating func rest(_ seconds: Double) {
        emit(seconds, rate: .zero, accel: .zero)
    }

    /// Rotates by the given degrees on each axis over `seconds`, at a constant rate.
    mutating func rotate(x: Double = 0, y: Double = 0, z: Double = 0, over seconds: Double) {
        let toRadiansPerSecond = Double.pi / 180 / seconds
        let rate = Vector3(x: x * toRadiansPerSecond, y: y * toRadiansPerSecond, z: z * toRadiansPerSecond)
        emit(seconds, rate: rate, accel: .zero)
    }

    /// Accelerates the phone straight up at `g` for `seconds`.
    mutating func jolt(up g: Double, over seconds: Double) {
        let down = gravity * (1 / gravity.magnitude)
        emit(seconds, rate: .zero, accel: down * -g)
    }

    private mutating func emit(_ seconds: Double, rate: Vector3, accel: Vector3) {
        let count = Int((seconds * Self.hz).rounded())
        for _ in 0..<count {
            time += 1 / Self.hz
            samples.append(MotionSample(time: time, rotationRate: rate, gravity: gravity, userAcceleration: accel))
        }
    }

    /// Feeds every sample to a fresh detector and returns what it saw.
    func detect(with thresholds: StuntDetector.Thresholds = StuntDetector.Thresholds()) -> [DetectedStunt] {
        var detector = StuntDetector(thresholds: thresholds)
        return samples.flatMap { detector.process($0) }
    }
}
