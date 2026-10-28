import SwiftUI

/// Maps world meters (y up) to canvas points (y down) for the current camera.
struct Viewport {
    let scale: Double
    let left: Double
    let top: Double
    let size: CGSize

    init(camera: Camera, size: CGSize) {
        self.size = size
        scale = Double(size.width) / camera.metersWide
        let metersHigh = Double(size.height) / scale
        // Never let the ground float up off the bottom of the screen.
        let centerY = max(camera.y, metersHigh / 2 - 1.5)
        left = camera.x - Double(size.width) / 2 / scale
        top = centerY + metersHigh / 2
    }

    var right: Double { left + Double(size.width) / scale }
    var bottom: Double { top - Double(size.height) / scale }

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: (x - left) * scale, y: (top - y) * scale)
    }

    func length(_ meters: Double) -> CGFloat { CGFloat(meters * scale) }

    var worldToScreen: CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: -left * scale, ty: top * scale)
    }

    /// Places something drawn in a body's own frame (meters, origin at its base) into the world.
    func placing(x: Double, y: Double, angle: Double) -> CGAffineTransform {
        CGAffineTransform(translationX: x, y: y).rotated(by: angle).concatenating(worldToScreen)
    }
}

struct CourseCanvas: View {
    let sim: LaunchSim
    let camera: Camera
    let papers: [Paper]
    let clock: Double

    var body: some View {
        Canvas { context, size in
            let view = Viewport(camera: camera, size: size)
            drawSky(&context, view)
            drawBackdrop(&context, view)
            drawGround(&context, view)
            drawLoop(&context, view)
            drawKicker(&context, view)
            drawVehicles(&context, view)
            drawLandingRamp(&context, view)
            drawCar(&context, view)
            drawPapers(&context, view)
        }
        .accessibilityLabel("The course, with the car at \(Int(sim.speed * 2.23694)) miles per hour")
    }

    // MARK: - Scenery

    private func drawSky(_ context: inout GraphicsContext, _ view: Viewport) {
        let rect = CGRect(origin: .zero, size: view.size)
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.05, green: 0.06, blue: 0.16),
                Color(red: 0.32, green: 0.18, blue: 0.3),
                Color(red: 0.95, green: 0.5, blue: 0.25),
            ]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: view.size.height)
        ))
        // A few fixed stars that drift slowly with the camera.
        for index in 0..<24 {
            let seed = Double(index)
            let sx = (seed * 97.3 - view.left * 2).truncatingRemainder(dividingBy: Double(view.size.width) + 40)
            let x = sx < 0 ? sx + Double(view.size.width) + 40 : sx
            let y = (seed * 37.7).truncatingRemainder(dividingBy: Double(view.size.height) * 0.45)
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.55)))
        }
    }

    /// Distant hills and a rocket test stand, scrolling slower than the course.
    private func drawBackdrop(_ context: inout GraphicsContext, _ view: Viewport) {
        let parallax = 0.25
        let horizon = view.point(0, 0).y
        var hills = Path()
        hills.move(to: CGPoint(x: 0, y: horizon))
        let width = Double(view.size.width)
        for step in 0...24 {
            let sx = Double(step) / 24 * width
            let worldX = view.left * parallax + sx / view.scale
            let height = 5 + 3 * sin(worldX * 0.08) + 2 * sin(worldX * 0.21)
            hills.addLine(to: CGPoint(x: sx, y: Double(horizon) - height * view.scale * 0.6))
        }
        hills.addLine(to: CGPoint(x: width, y: Double(horizon)))
        hills.closeSubpath()
        context.fill(hills, with: .color(Color(red: 0.16, green: 0.1, blue: 0.14)))

        // Test stand: a lattice tower standing far behind the loop.
        let towerScreenX = (60 - view.left * parallax) * view.scale * 0.6
        let towerHeight = 42 * view.scale * 0.6
        let towerWidth = 6 * view.scale * 0.6
        let base = Double(horizon)
        var tower = Path()
        tower.addRect(CGRect(x: towerScreenX, y: base - towerHeight, width: towerWidth, height: towerHeight))
        context.stroke(tower, with: .color(.black.opacity(0.55)), lineWidth: 2)
        var lattice = Path()
        let rungs = 9
        for rung in 0..<rungs {
            let y0 = base - towerHeight * Double(rung) / Double(rungs)
            let y1 = base - towerHeight * Double(rung + 1) / Double(rungs)
            lattice.move(to: CGPoint(x: towerScreenX, y: y0))
            lattice.addLine(to: CGPoint(x: towerScreenX + towerWidth, y: y1))
            lattice.move(to: CGPoint(x: towerScreenX + towerWidth, y: y0))
            lattice.addLine(to: CGPoint(x: towerScreenX, y: y1))
        }
        context.stroke(lattice, with: .color(.black.opacity(0.45)), lineWidth: 1)
        let beacon = CGRect(x: towerScreenX + towerWidth / 2 - 2, y: base - towerHeight - 5, width: 4, height: 4)
        context.fill(Path(ellipseIn: beacon), with: .color(.red.opacity(sin(clock * 3) > 0 ? 0.9 : 0.25)))
    }

    private func drawGround(_ context: inout GraphicsContext, _ view: Viewport) {
        let groundTop = view.point(0, 0).y
        let ground = CGRect(x: 0, y: groundTop, width: view.size.width, height: max(0, view.size.height - groundTop))
        context.fill(Path(ground), with: .color(Color(red: 0.1, green: 0.1, blue: 0.11)))
        var line = Path()
        line.move(to: CGPoint(x: 0, y: groundTop))
        line.addLine(to: CGPoint(x: view.size.width, y: groundTop))
        context.stroke(line, with: .color(.white.opacity(0.35)), lineWidth: 1.5)

        // Marker posts every 5 m so speed reads on screen.
        let first = Int((view.left / 5).rounded(.down))
        let last = Int((view.right / 5).rounded(.up))
        for mark in first...last {
            let x = Double(mark) * 5
            let isTen = mark % 2 == 0
            var post = Path()
            post.move(to: view.point(x, 0))
            post.addLine(to: view.point(x, isTen ? -0.6 : -0.3))
            context.stroke(post, with: .color(.white.opacity(isTen ? 0.4 : 0.2)), lineWidth: 1)
            if isTen && mark >= 0 && mark % 4 == 0 {
                context.draw(
                    Text("\(mark * 5) m").font(.form(9)).foregroundColor(.white.opacity(0.35)),
                    at: view.point(x, -1.2)
                )
            }
        }
        context.draw(
            Text("START").font(.form(10, weight: .bold)).foregroundColor(.white.opacity(0.6)),
            at: view.point(0, -1.4)
        )
    }

    private func drawLoop(_ context: inout GraphicsContext, _ view: Viewport) {
        let course = sim.course
        let center = view.point(course.loopX, course.loopRadius)
        let radius = view.length(course.loopRadius + 0.2)
        guard center.x + radius > 0 && center.x - radius < view.size.width else { return }

        // Scaffolding.
        var scaffold = Path()
        for offset in [-0.75, -0.35, 0.35, 0.75] {
            let x = course.loopX + course.loopRadius * offset
            let ringY = course.loopRadius - course.loopRadius * (1 - offset * offset).squareRoot()
            scaffold.move(to: view.point(x, 0))
            scaffold.addLine(to: view.point(x, ringY))
        }
        context.stroke(scaffold, with: .color(.white.opacity(0.18)), lineWidth: 2)

        let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.stroke(ring, with: .color(Color(white: 0.55)), lineWidth: max(3, view.length(0.35)))
        let outer = view.length(course.loopRadius + 0.6)
        let rail = Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
        context.stroke(rail, with: .color(.white.opacity(0.25)), lineWidth: 1)

        context.draw(
            Text("SUCTION ZONE").font(.form(11, weight: .heavy)).foregroundColor(.fanTeal.opacity(0.8)),
            at: view.point(course.loopX, course.loopRadius * 2 + 1.6)
        )
    }

    private func drawKicker(_ context: inout GraphicsContext, _ view: Viewport) {
        let course = sim.course
        var ramp = Path()
        ramp.move(to: view.point(course.kickerStart, 0))
        for step in 0...16 {
            let psi = course.kickerAngle * Double(step) / 16
            ramp.addLine(to: view.point(
                course.kickerStart + course.kickerRadius * sin(psi),
                course.kickerRadius * (1 - cos(psi))
            ))
        }
        ramp.addLine(to: view.point(course.lipX, 0))
        ramp.closeSubpath()
        context.fill(ramp, with: .color(Color(white: 0.32)))
        context.stroke(ramp, with: .color(Color(white: 0.7)), lineWidth: 1.5)
    }

    private func drawVehicles(_ context: inout GraphicsContext, _ view: Viewport) {
        for vehicle in sim.course.vehicles {
            guard view.point(vehicle.x1, 0).x > 0 && view.point(vehicle.x0, 0).x < view.size.width else { continue }
            let transform = view.placing(x: vehicle.x0, y: 0, angle: 0)
            let length = vehicle.x1 - vehicle.x0
            let (body, color) = Self.vehicleBody(vehicle.style, length: length, height: vehicle.height)
            context.fill(body.applying(transform), with: .color(color))
            context.stroke(body.applying(transform), with: .color(.black.opacity(0.35)), lineWidth: 1)
            for wheelX in [length * 0.18, length * 0.82] {
                let wheel = Path(ellipseIn: CGRect(x: wheelX - 0.38, y: 0, width: 0.76, height: 0.76))
                context.fill(wheel.applying(transform), with: .color(Color(white: 0.08)))
            }
            context.draw(
                Text(vehicle.name.uppercased()).font(.form(9, weight: .bold)).foregroundColor(.white.opacity(0.7)),
                at: view.point((vehicle.x0 + vehicle.x1) / 2, vehicle.height + 0.9)
            )
        }
    }

    /// Side profiles of the parked lineup, origin at the rear wheel's ground line.
    private static func vehicleBody(_ style: Course.VehicleStyle, length l: Double, height h: Double) -> (Path, Color) {
        var path = Path()
        switch style {
        case .sedan, .crossover, .robotaxi:
            let shoulder = h * (style == .robotaxi ? 0.6 : 0.55)
            path.move(to: CGPoint(x: 0.1, y: 0.35))
            path.addLine(to: CGPoint(x: 0, y: shoulder))
            path.addQuadCurve(to: CGPoint(x: l * 0.45, y: h), control: CGPoint(x: l * 0.2, y: h))
            path.addQuadCurve(to: CGPoint(x: l * 0.85, y: shoulder), control: CGPoint(x: l * 0.68, y: h))
            path.addLine(to: CGPoint(x: l, y: shoulder * 0.75))
            path.addLine(to: CGPoint(x: l - 0.1, y: 0.35))
            path.closeSubpath()
            let color: Color = style == .sedan ? Color(white: 0.75) : style == .crossover ? Color(white: 0.92) : Color(red: 0.8, green: 0.68, blue: 0.4)
            return (path, color)
        case .truck:
            path.move(to: CGPoint(x: 0, y: 0.4))
            path.addLine(to: CGPoint(x: 0, y: h * 0.62))
            path.addLine(to: CGPoint(x: l * 0.52, y: h))
            path.addLine(to: CGPoint(x: l, y: h * 0.62))
            path.addLine(to: CGPoint(x: l, y: 0.4))
            path.closeSubpath()
            return (path, Color(red: 0.62, green: 0.64, blue: 0.66))
        case .semi:
            path.addRect(CGRect(x: 0, y: 0.5, width: l * 0.62, height: 0.6))
            path.move(to: CGPoint(x: l * 0.6, y: 0.5))
            path.addLine(to: CGPoint(x: l * 0.6, y: h))
            path.addLine(to: CGPoint(x: l * 0.88, y: h))
            path.addQuadCurve(to: CGPoint(x: l, y: h * 0.45), control: CGPoint(x: l, y: h))
            path.addLine(to: CGPoint(x: l, y: 0.5))
            path.closeSubpath()
            return (path, Color(white: 0.85))
        }
    }

    private func drawLandingRamp(_ context: inout GraphicsContext, _ view: Viewport) {
        let course = sim.course
        guard view.point(course.rampBottom, 0).x > 0 && view.point(course.rampTop, 0).x < view.size.width else { return }
        var ramp = Path()
        ramp.move(to: view.point(course.rampTop, 0))
        ramp.addLine(to: view.point(course.rampTop, course.rampHeight))
        ramp.addLine(to: view.point(course.rampBottom, 0))
        ramp.closeSubpath()
        context.fill(ramp, with: .color(Color(white: 0.3)))
        context.stroke(ramp, with: .color(Color(white: 0.75)), lineWidth: 1.5)

        let midX = (course.rampTop + course.rampBottom) / 2
        let midY = course.ground(at: midX).height
        context.draw(
            Text("LAND HERE").font(.form(11, weight: .heavy)).foregroundColor(.yellow.opacity(0.85)),
            at: view.point(midX, midY + 2.2)
        )
    }

    // MARK: - The car

    private func drawCar(_ context: inout GraphicsContext, _ view: Viewport) {
        let transform = view.placing(x: sim.x, y: sim.y, angle: sim.angle)
        let onTrack = sim.gripG != nil

        // Ground-sealing glow and air being pulled out from under the car.
        if onTrack && sim.fanRPM > 0.05 {
            let glow = Path(roundedRect: CGRect(x: -1.9, y: -0.05, width: 3.8, height: 0.22), cornerRadius: 0.1)
            context.fill(glow.applying(transform), with: .color(Color.fanTeal.opacity(0.75 * sim.fanRPM)))
            var swirl = Path()
            for index in 0..<4 {
                let phase = (clock * 6 + Double(index) * 0.25).truncatingRemainder(dividingBy: 1)
                let x = -1.5 + Double(index)
                swirl.move(to: CGPoint(x: x, y: 0.1 + phase * 0.25))
                swirl.addLine(to: CGPoint(x: x + 0.25, y: 0.1 + phase * 0.25))
            }
            context.stroke(swirl.applying(transform), with: .color(.white.opacity(0.6 * sim.fanRPM)), lineWidth: 1.5)
        }

        let flicker = 0.75 + 0.25 * sin(clock * 47)
        if sim.boostFiring {
            var plume = Path()
            plume.move(to: CGPoint(x: -2.15, y: 0.38))
            plume.addLine(to: CGPoint(x: -2.15 - 3.2 * flicker, y: 0.55))
            plume.addLine(to: CGPoint(x: -2.15, y: 0.72))
            plume.closeSubpath()
            context.fill(plume.applying(transform), with: .color(Color.thrusterBlue.opacity(0.85)))
            var core = Path()
            core.move(to: CGPoint(x: -2.15, y: 0.47))
            core.addLine(to: CGPoint(x: -2.15 - 1.6 * flicker, y: 0.55))
            core.addLine(to: CGPoint(x: -2.15, y: 0.63))
            core.closeSubpath()
            context.fill(core.applying(transform), with: .color(.white))
        }
        if sim.liftFiring {
            var plumes = Path()
            for nozzleX in [-1.2, 1.2] {
                plumes.move(to: CGPoint(x: nozzleX - 0.18, y: 0.25))
                plumes.addLine(to: CGPoint(x: nozzleX, y: 0.25 - 2.4 * flicker))
                plumes.addLine(to: CGPoint(x: nozzleX + 0.18, y: 0.25))
                plumes.closeSubpath()
            }
            context.fill(plumes.applying(transform), with: .color(Color.thrusterBlue.opacity(0.8)))
        }

        let body = Self.roadsterBody
        context.fill(body.applying(transform), with: .linearGradient(
            Gradient(colors: [Color(red: 1, green: 0.25, blue: 0.28), .roadsterRed, Color(red: 0.5, green: 0.02, blue: 0.06)]),
            startPoint: view.point(sim.x, sim.y + 1.2),
            endPoint: view.point(sim.x, sim.y)
        ))
        context.stroke(body.applying(transform), with: .color(.black.opacity(0.5)), lineWidth: 1)
        context.fill(Self.roadsterGlass.applying(transform), with: .color(Color(red: 0.08, green: 0.1, blue: 0.16)))
        for wheelX in [-1.35, 1.35] {
            let tire = Path(ellipseIn: CGRect(x: wheelX - 0.36, y: 0, width: 0.72, height: 0.72))
            context.fill(tire.applying(transform), with: .color(Color(white: 0.06)))
            let hub = Path(ellipseIn: CGRect(x: wheelX - 0.17, y: 0.19, width: 0.34, height: 0.34))
            context.fill(hub.applying(transform), with: .color(Color(white: 0.7)))
        }
    }

    /// A low two-door wedge, 4.4 m long, origin on the ground under the middle of the car.
    private static let roadsterBody: Path = {
        var path = Path()
        path.move(to: CGPoint(x: -2.0, y: 0.25))
        path.addLine(to: CGPoint(x: -2.2, y: 0.4))
        path.addLine(to: CGPoint(x: -2.15, y: 0.78))
        path.addQuadCurve(to: CGPoint(x: -0.55, y: 1.12), control: CGPoint(x: -1.4, y: 1.0))
        path.addQuadCurve(to: CGPoint(x: 0.45, y: 1.1), control: CGPoint(x: -0.05, y: 1.2))
        path.addLine(to: CGPoint(x: 1.15, y: 0.82))
        path.addQuadCurve(to: CGPoint(x: 2.2, y: 0.45), control: CGPoint(x: 2.1, y: 0.72))
        path.addLine(to: CGPoint(x: 2.1, y: 0.25))
        path.closeSubpath()
        return path
    }()

    private static let roadsterGlass: Path = {
        var path = Path()
        path.move(to: CGPoint(x: -0.85, y: 0.9))
        path.addQuadCurve(to: CGPoint(x: 0.35, y: 1.04), control: CGPoint(x: -0.2, y: 1.1))
        path.addLine(to: CGPoint(x: 0.95, y: 0.86))
        path.closeSubpath()
        return path
    }()

    private func drawPapers(_ context: inout GraphicsContext, _ view: Viewport) {
        for paper in papers {
            let sheet = Path(CGRect(x: -0.25, y: -0.35, width: 0.5, height: 0.7))
            let transform = view.placing(x: paper.x, y: paper.y, angle: paper.angle)
            context.fill(sheet.applying(transform), with: .color(.claimPaper))
            var lines = Path()
            for row in 0..<3 {
                let y = 0.15 - Double(row) * 0.15
                lines.move(to: CGPoint(x: -0.15, y: y))
                lines.addLine(to: CGPoint(x: 0.15, y: y))
            }
            context.stroke(lines.applying(transform), with: .color(.claimInk.opacity(0.5)), lineWidth: 0.5)
        }
    }
}
