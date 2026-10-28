import Foundation

/// What the player is pressing this instant.
struct Controls: Equatable {
    var throttle = false
    /// Rear cold-gas thrusters.
    var boost = false
    /// Underbody cold-gas thrusters, for softening landings.
    var lift = false
    /// Suction fan switch. The fan still takes time to spin up and down.
    var fan = false
    /// Attitude in the air: -1 rotates clockwise (nose down), 1 counterclockwise (nose up).
    var spin = 0.0
}

/// The knobs, tuned against a prototype so that the loop needs the fan or a boost,
/// leaving the fan on overheats it, and full boost from a standstill just beats 0.81 s to 60 mph.
struct Tuning {
    var gravity = 9.81
    /// Motor acceleration at low speed, m/s².
    var motorAccel = 9.0
    /// Above ~10 m/s the motor is power-limited: acceleration = power / speed.
    var motorPower = 90.0
    /// Tire friction: traction can't exceed this times the load pressing the car into the track.
    var tireGrip = 1.0
    var dragPerSpeedSquared = 0.0025

    var boostAccel = 28.0
    var liftAccel = 22.0
    /// Fraction of the air tanks each firing thruster bank uses per second.
    var airDrainPerSecond = 0.25

    /// Full-speed suction, in g.
    var fanSuctionG = 2.0
    var fanDragAccel = 1.5
    var fanSpinUpPerSecond = 2.0
    var fanHeatPerSecond = 0.25
    var fanCoolPerSecond = 0.2
    var fanUnlockTemperature = 0.35

    /// Max attitude rate in the air, rad/s.
    var spinRate = 6.0
    /// Landing limits: angle to the surface and speed into it.
    var maxLandingAngleDegrees = 25.0
    var maxLandingSpeed = 9.0
    var rolloutBrake = 9.0
    var crashDuration = 2.0
}

enum Segment: Equatable {
    case staging
    case runway
    case loop
    case flat
    case kicker
    case air
    case rollout
    case crashed
    case done
}

enum CrashReason: Equatable {
    case fellOffLoop
    case stalled
    case hitVehicle(String)
    case hitRampWall
    case onRoof
    case wrongAngle
    case hardLanding
}

enum SimEvent: Equatable {
    case launched
    case hitSixty(seconds: Double)
    case fanOverheated
    case fanRecovered
    case outOfAir
    case enteredLoop
    case completedLoop
    case fellOffLoop
    case tookOff(speed: Double)
    case cleared(vehicle: String)
    case landed(impactSpeed: Double)
    case crashed(CrashReason)
    case finished
}

/// One attempt at the course. Step it at a fixed rate with the player's controls;
/// read its state to draw the car and the cockpit.
struct LaunchSim {
    static let sixtyMph = 26.8224

    let course: Course
    let tuning: Tuning

    private(set) var segment: Segment = .staging
    /// Seconds since launch.
    private(set) var time = 0.0

    private(set) var x = 0.0
    private(set) var y = 0.0
    /// Pitch in radians, counterclockwise from level.
    private(set) var angle = 0.0
    /// Speed along the track while on it.
    private(set) var trackSpeed = 0.0
    private(set) var vx = 0.0
    private(set) var vy = 0.0
    private(set) var angularVelocity = 0.0

    /// 1 is full COPVs, 0 is empty.
    private(set) var air = 1.0
    private(set) var fanRPM = 0.0
    private(set) var fanTemperature = 0.0
    private(set) var fanLocked = false
    private(set) var boostFiring = false
    private(set) var liftFiring = false

    /// Load pressing the car into the track, in g, including suction. Nil in the air.
    private(set) var gripG: Double?
    private(set) var minLoopGrip = Double.infinity
    private(set) var loopCompleted = false
    private(set) var sixtyTime: Double?
    private(set) var takeoffSpeed: Double?
    private(set) var clearedCount = 0
    /// Rotation since takeoff, radians. Positive is nose-up (a backflip when heading right).
    private(set) var flipRotation = 0.0
    private(set) var airtime = 0.0
    private(set) var maxAltitude = 0.0
    private(set) var landingImpact: Double?
    private(set) var crashReason: CrashReason?

    private var trackParam = 0.0
    private var fellOff = false
    private var crashTimer = 0.0
    private var pendingEvents: [SimEvent] = []

    init(course: Course = Course(), tuning: Tuning = Tuning()) {
        self.course = course
        self.tuning = tuning
    }

    // MARK: - Reading

    var speed: Double {
        switch segment {
        case .air, .crashed: return (vx * vx + vy * vy).squareRoot()
        default: return trackSpeed
        }
    }

    var altitude: Double { max(0, y - course.ground(at: x).height) }
    var isInverted: Bool { cos(angle) < -0.2 }
    var isOver: Bool { segment == .done }
    var landed: Bool { isOver && crashReason == nil }

    /// Full turns completed in the air, signed: positive backflips, negative frontflips.
    var flips: Int { Int((flipRotation / (2 * .pi)).rounded()) }

    mutating func drainEvents() -> [SimEvent] {
        defer { pendingEvents.removeAll() }
        return pendingEvents
    }

    // MARK: - Stepping

    mutating func step(_ dt: Double, controls: Controls) {
        guard segment != .done else { return }
        if segment == .staging && (controls.throttle || controls.boost) {
            segment = .runway
            emit(.launched)
        }
        if segment != .staging { time += dt }

        updateFan(dt, on: controls.fan)
        updateThrusters(dt, controls: controls)

        switch segment {
        case .staging, .done: break
        case .runway, .loop, .flat, .kicker: stepTrack(dt, controls: controls)
        case .air: stepAir(dt, controls: controls)
        case .rollout: stepRollout(dt)
        case .crashed: stepCrash(dt)
        }
    }

    private mutating func updateFan(_ dt: Double, on: Bool) {
        let target: Double = on && !fanLocked ? 1 : 0
        let change = min(abs(target - fanRPM), tuning.fanSpinUpPerSecond * dt)
        fanRPM += target > fanRPM ? change : -change

        fanTemperature += (tuning.fanHeatPerSecond * fanRPM - tuning.fanCoolPerSecond * (1 - fanRPM)) * dt
        fanTemperature = min(1, max(0, fanTemperature))
        if fanTemperature >= 1 && !fanLocked {
            fanLocked = true
            emit(.fanOverheated)
        } else if fanLocked && fanTemperature <= tuning.fanUnlockTemperature {
            fanLocked = false
            emit(.fanRecovered)
        }
    }

    private mutating func updateThrusters(_ dt: Double, controls: Controls) {
        let live = air > 0 && segment != .staging && segment != .crashed && segment != .rollout && segment != .done
        boostFiring = live && controls.boost
        liftFiring = live && controls.lift && segment == .air
        let banks = (boostFiring ? 1.0 : 0) + (liftFiring ? 1.0 : 0)
        guard banks > 0 else { return }
        air = max(0, air - tuning.airDrainPerSecond * banks * dt)
        // Thrusters stop firing once the tanks are empty, so this runs once.
        if air == 0 { emit(.outOfAir) }
    }

    private mutating func stepTrack(_ dt: Double, controls: Controls) {
        let g = tuning.gravity
        let radius: Double?
        switch segment {
        case .loop: radius = course.loopRadius
        case .kicker: radius = course.kickerRadius
        default: radius = nil
        }

        let centripetal = radius.map { trackSpeed * trackSpeed / $0 } ?? 0
        let load = centripetal + g * cos(trackParam) + tuning.fanSuctionG * g * fanRPM
        gripG = load / g
        if segment == .loop { minLoopGrip = min(minLoopGrip, load / g) }

        guard load >= 0 else {
            // Not enough speed or suction to stay on the ceiling.
            fellOff = true
            emit(.fellOffLoop)
            takeOff(speed: trackSpeed, announce: false)
            return
        }

        let motor = controls.throttle
            ? min(tuning.motorAccel, tuning.motorPower / max(trackSpeed, 1), tuning.tireGrip * load)
            : 0
        let accel = motor
            + (boostFiring ? tuning.boostAccel : 0)
            - g * sin(trackParam)
            - tuning.dragPerSpeedSquared * trackSpeed * trackSpeed
            - tuning.fanDragAccel * fanRPM
        trackSpeed += accel * dt
        if segment == .runway || segment == .flat { trackSpeed = max(0, trackSpeed) }

        if sixtyTime == nil && trackSpeed >= Self.sixtyMph {
            sixtyTime = time
            emit(.hitSixty(seconds: time))
        }

        if radius != nil && trackSpeed <= 0.3 {
            crash(.stalled)
            return
        }

        switch segment {
        case .runway:
            x += trackSpeed * dt
            if x >= course.loopX {
                segment = .loop
                trackParam = (x - course.loopX) / course.loopRadius
                emit(.enteredLoop)
            }
        case .loop:
            trackParam += trackSpeed / course.loopRadius * dt
            if trackParam >= 2 * .pi {
                segment = .flat
                x = course.loopX + (trackParam - 2 * .pi) * course.loopRadius
                trackParam = 0
                loopCompleted = true
                emit(.completedLoop)
            }
        case .flat:
            x += trackSpeed * dt
            if x >= course.kickerStart {
                segment = .kicker
                trackParam = (x - course.kickerStart) / course.kickerRadius
            }
        case .kicker:
            trackParam += trackSpeed / course.kickerRadius * dt
            if trackParam >= course.kickerAngle {
                trackParam = course.kickerAngle
                placeOnTrack()
                takeOff(speed: trackSpeed, announce: true)
                return
            }
        default:
            break
        }
        placeOnTrack()
    }

    private mutating func placeOnTrack() {
        switch segment {
        case .loop:
            x = course.loopX + course.loopRadius * sin(trackParam)
            y = course.loopRadius * (1 - cos(trackParam))
            angle = trackParam
        case .kicker:
            x = course.kickerStart + course.kickerRadius * sin(trackParam)
            y = course.kickerRadius * (1 - cos(trackParam))
            angle = trackParam
        default:
            y = 0
            angle = 0
        }
    }

    private mutating func takeOff(speed: Double, announce: Bool) {
        segment = .air
        vx = speed * cos(angle)
        vy = speed * sin(angle)
        angularVelocity = 0
        flipRotation = 0
        gripG = nil
        if announce {
            takeoffSpeed = speed
            emit(.tookOff(speed: speed))
        }
    }

    private mutating func stepAir(_ dt: Double, controls: Controls) {
        let g = tuning.gravity
        let target = max(-1, min(1, controls.spin)) * tuning.spinRate
        angularVelocity += (target - angularVelocity) * min(1, 20 * dt)
        angle += angularVelocity * dt
        flipRotation += angularVelocity * dt

        let v = (vx * vx + vy * vy).squareRoot()
        let thrust = boostFiring ? tuning.boostAccel : 0
        let lift = liftFiring ? tuning.liftAccel : 0
        let drag = tuning.dragPerSpeedSquared * v
        vx += (thrust * cos(angle) - lift * sin(angle) - drag * vx) * dt
        vy += (-g + thrust * sin(angle) + lift * cos(angle) - drag * vy) * dt
        x += vx * dt
        y += vy * dt
        airtime += dt
        maxAltitude = max(maxAltitude, y)

        let points = contactPoints()
        for vehicle in course.vehicles {
            if points.contains(where: { $0.x >= vehicle.x0 && $0.x <= vehicle.x1 && $0.y <= vehicle.height }) {
                crash(.hitVehicle(vehicle.name))
                return
            }
        }
        if !fellOff {
            while clearedCount < course.vehicles.count && x > course.vehicles[clearedCount].x1 {
                emit(.cleared(vehicle: course.vehicles[clearedCount].name))
                clearedCount += 1
            }
        }
        if let point = points.first(where: { $0.y <= course.ground(at: $0.x).height }) {
            touchDown(on: course.ground(at: point.x))
        }
    }

    /// Wheels front, middle and back, plus the two roof corners, in world space.
    private func contactPoints() -> [(x: Double, y: Double)] {
        let local: [(Double, Double)] = [(-2, 0), (0, 0), (2, 0), (-1.2, 1.1), (1.2, 1.1)]
        let c = cos(angle), s = sin(angle)
        return local.map { (x: x + $0.0 * c - $0.1 * s, y: y + $0.0 * s + $0.1 * c) }
    }

    private mutating func touchDown(on surface: Course.Surface) {
        let normalX = -sin(surface.slope), normalY = cos(surface.slope)
        let impact = -(vx * normalX + vy * normalY)
        landingImpact = impact

        var relative = (angle - surface.slope).truncatingRemainder(dividingBy: 2 * .pi)
        if relative > .pi { relative -= 2 * .pi }
        if relative < -.pi { relative += 2 * .pi }
        let relativeDegrees = abs(relative) * 180 / .pi

        if fellOff {
            crash(.fellOffLoop)
        } else if surface.slope != 0 && x < course.rampTop + 0.5 && y < course.rampHeight - 0.3 {
            crash(.hitRampWall)
        } else if relativeDegrees > 120 {
            crash(.onRoof)
        } else if relativeDegrees > tuning.maxLandingAngleDegrees {
            crash(.wrongAngle)
        } else if impact > tuning.maxLandingSpeed {
            crash(.hardLanding)
        } else {
            segment = .rollout
            trackSpeed = max(0, vx * cos(surface.slope) + vy * sin(surface.slope))
            y = surface.height
            angle = surface.slope
            emit(.landed(impactSpeed: impact))
        }
    }

    private mutating func stepRollout(_ dt: Double) {
        let surface = course.ground(at: x)
        trackSpeed = max(0, trackSpeed + (-tuning.rolloutBrake - tuning.gravity * sin(surface.slope)) * dt)
        x += trackSpeed * cos(surface.slope) * dt
        let next = course.ground(at: x)
        y = next.height
        angle = next.slope
        // Came up short and rolled into the parked lineup.
        if let vehicle = course.vehicles.first(where: { x + 2 >= $0.x0 && x - 2 <= $0.x1 }) {
            crash(.hitVehicle(vehicle.name))
            return
        }
        if trackSpeed == 0 {
            segment = .done
            emit(.finished)
        }
    }

    private mutating func crash(_ reason: CrashReason) {
        if segment != .air {
            vx = trackSpeed * cos(angle)
            vy = trackSpeed * sin(angle)
        }
        if case .hitVehicle = reason {
            vx *= 0.4
            vy = 5
        }
        segment = .crashed
        crashReason = reason
        angularVelocity = vx >= 0 ? -7 : 7
        gripG = nil
        emit(.crashed(reason))
    }

    /// Tumble and bounce for a couple of seconds so the crash reads on screen.
    private mutating func stepCrash(_ dt: Double) {
        crashTimer += dt
        vy -= tuning.gravity * dt
        x += vx * dt
        y += vy * dt
        angle += angularVelocity * dt
        let ground = course.ground(at: x).height
        if y < ground {
            y = ground
            vy = abs(vy) * 0.35
            vx *= 0.6
            angularVelocity *= 0.7
        }
        if crashTimer >= tuning.crashDuration {
            segment = .done
            emit(.finished)
        }
    }

    private mutating func emit(_ event: SimEvent) {
        pendingEvents.append(event)
    }
}
