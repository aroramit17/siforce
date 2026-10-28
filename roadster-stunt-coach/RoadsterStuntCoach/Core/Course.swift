import Foundation

/// The reveal course, in meters, seen from the side: x runs along the course, y is up.
///
///     staging → runway → the loop → short flat → kicker ramp → five parked vehicles → landing ramp → runout
///
/// The loop is a full circle the car rides on the inside of, so the top is driven upside down.
/// The kicker launches the car over the parked vehicles and the landing ramp slopes back down.
struct Course {
    enum VehicleStyle: CaseIterable {
        case sedan
        case crossover
        case truck
        case robotaxi
        case semi
    }

    struct Vehicle: Equatable {
        let name: String
        let style: VehicleStyle
        let x0: Double
        let x1: Double
        let height: Double
    }

    struct Surface: Equatable {
        let height: Double
        /// Radians; negative slopes run downhill in the direction of travel.
        let slope: Double
    }

    let loopX: Double
    let loopRadius: Double
    let kickerStart: Double
    let kickerRadius: Double
    let kickerAngle: Double
    let lipX: Double
    let lipY: Double
    let vehicles: [Vehicle]
    let rampTop: Double
    let rampHeight: Double
    let rampSlope: Double
    let rampBottom: Double
    let finishX: Double

    init(
        loopX: Double = 22,
        loopRadius: Double = 14,
        flatAfterLoop: Double = 10,
        kickerRadius: Double = 16,
        kickerAngleDegrees: Double = 25,
        firstVehicleGap: Double = 6,
        vehicleSpacing: Double = 1,
        landingRampDistance: Double = 45,
        rampHeight: Double = 7,
        rampSlopeDegrees: Double = 12
    ) {
        let kickerStart = loopX + flatAfterLoop
        let kickerAngle = kickerAngleDegrees * .pi / 180
        let lipX = kickerStart + kickerRadius * sin(kickerAngle)
        self.loopX = loopX
        self.loopRadius = loopRadius
        self.kickerStart = kickerStart
        self.kickerRadius = kickerRadius
        self.kickerAngle = kickerAngle
        self.lipX = lipX
        lipY = kickerRadius * (1 - cos(kickerAngle))

        let lineup: [(String, VehicleStyle, Double, Double)] = [
            ("Sedan", .sedan, 4.7, 1.45),
            ("Crossover", .crossover, 4.75, 1.65),
            ("Angular Truck", .truck, 5.7, 1.9),
            ("Robotaxi", .robotaxi, 4.2, 1.5),
            ("Semi", .semi, 7.0, 3.9),
        ]
        var x = lipX + firstVehicleGap
        var parked: [Vehicle] = []
        for (name, style, length, height) in lineup {
            parked.append(Vehicle(name: name, style: style, x0: x, x1: x + length, height: height))
            x += length + vehicleSpacing
        }
        vehicles = parked

        let rampTop = lipX + landingRampDistance
        let rampBottom = rampTop + rampHeight / tan(rampSlopeDegrees * .pi / 180)
        self.rampTop = rampTop
        self.rampHeight = rampHeight
        rampSlope = -rampSlopeDegrees * .pi / 180
        self.rampBottom = rampBottom
        finishX = rampBottom + 90
    }

    /// The ground under `x`: the landing ramp where it is, flat tarmac everywhere else.
    /// The loop and kicker are rails the car rides, not ground.
    func ground(at x: Double) -> Surface {
        if x >= rampTop && x <= rampBottom {
            return Surface(height: rampHeight + (x - rampTop) * tan(rampSlope), slope: rampSlope)
        }
        return Surface(height: 0, slope: 0)
    }
}
