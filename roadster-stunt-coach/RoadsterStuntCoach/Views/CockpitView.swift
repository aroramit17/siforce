import SwiftUI

/// The run screen: the course on top, the dashboard below.
struct CockpitView: View {
    @Environment(GameController.self) private var game

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CourseCanvas(sim: game.sim, camera: game.camera, papers: game.papers, clock: game.clock)
                    .ignoresSafeArea()
                HUDOverlay()
            }
            DashboardView()
                .frame(height: 148)
        }
        .background(Color.dashPanel.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

private struct HUDOverlay: View {
    @Environment(GameController.self) private var game

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                Button {
                    game.quitToTitle()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(9)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Quit to garage")
                Spacer()
                CautionPanel(sim: game.sim)
                Spacer()
                SixtyTimer(seconds: game.sim.sixtyTime, running: game.sim.segment != .staging, elapsed: game.sim.time)
            }
            Spacer()
            if let callout = game.callout, game.clock < callout.until {
                Text(callout.text)
                    .font(.poster(36))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 6)
                    .id(callout.id)
                    .transition(.scale(scale: 1.4).combined(with: .opacity))
            }
            Spacer()
            HStack(alignment: .bottom) {
                if !game.steeringWithTilt {
                    HoldButton(title: "NOSE UP", systemImage: "arrow.counterclockwise", tint: .white, diameter: 56, isPressed: spinBinding(1))
                }
                Spacer()
                Text(game.coachLine)
                    .font(.poster(18))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 4)
                    .multilineTextAlignment(.center)
                Spacer()
                if !game.steeringWithTilt {
                    HoldButton(title: "NOSE DN", systemImage: "arrow.clockwise", tint: .white, diameter: 56, isPressed: spinBinding(-1))
                }
            }
        }
        .padding(12)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: game.callout)
    }

    private func spinBinding(_ direction: Double) -> Binding<Bool> {
        Binding(
            get: { game.spinButtons == direction },
            set: { pressed in
                if pressed {
                    game.spinButtons = direction
                } else if game.spinButtons == direction {
                    game.spinButtons = 0
                }
            }
        )
    }
}

private struct CautionPanel: View {
    let sim: LaunchSim

    var body: some View {
        let grip = sim.gripG
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Annunciator(title: "GRIP LOW", lit: (grip ?? 1) < 0.4)
                Annunciator(title: "INVERTED", lit: sim.isInverted && sim.segment == .loop, color: .yellow)
                Annunciator(title: "FAN HOT", lit: sim.fanTemperature > 0.75)
            }
            GridRow {
                Annunciator(title: "LOW AIR", lit: sim.air < 0.2)
                Annunciator(title: "BOOST", lit: sim.boostFiring, color: .thrusterBlue)
                Annunciator(title: "LIFT", lit: sim.liftFiring, color: .thrusterBlue)
            }
        }
        .frame(width: 210)
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SixtyTimer: View {
    let seconds: Double?
    let running: Bool
    let elapsed: Double

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("0–60 MPH")
                .font(.form(9, weight: .heavy))
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f s", seconds ?? (running ? elapsed : 0)))
                .font(.form(22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(timeColor)
            Text("REVEAL CLAIM 0.81 s")
                .font(.form(8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var timeColor: Color {
        guard let seconds else { return .white }
        return seconds < Scorer.revealSixtyTime ? .green : .yellow
    }
}

private struct DashboardView: View {
    @Environment(GameController.self) private var game

    var body: some View {
        @Bindable var game = game
        let sim = game.sim
        let grip = sim.gripG
        HStack(alignment: .center, spacing: 10) {
            FanSwitch(isOn: game.controls.fan, rpm: sim.fanRPM, locked: sim.fanLocked) {
                game.toggleFan()
            }
            HoldButton(
                title: "THROTTLE",
                systemImage: "bolt.car.fill",
                tint: .green,
                diameter: 84,
                isPressed: $game.controls.throttle
            )

            Spacer(minLength: 0)

            DialGauge(title: "SPEED", value: sim.speed * 2.23694, range: 0...140, unit: "MPH", diameter: 72)
            DialGauge(
                title: "COPV AIR",
                value: sim.air * 4_500,
                range: 0...4_500,
                unit: "PSI",
                warning: sim.air < 0.2,
                diameter: 72
            )
            VStack(spacing: 7) {
                BarGauge(title: "FAN RPM", fraction: sim.fanRPM, tint: .fanTeal)
                BarGauge(
                    title: "FAN TEMP",
                    fraction: sim.fanTemperature,
                    tint: sim.fanTemperature > 0.75 ? .roadsterRed : .orange
                )
                BarGauge(
                    title: "GRIP",
                    fraction: (grip ?? 0) / 4,
                    tint: (grip ?? 1) < 0.4 ? .roadsterRed : .gaugeCyan,
                    trailing: grip.map { String(format: "%.1f g", $0) } ?? "AIR"
                )
                BarGauge(
                    title: "ALT",
                    fraction: sim.altitude / 15,
                    tint: .white.opacity(0.7),
                    trailing: String(format: "%.0f ft", sim.altitude * 3.281)
                )
            }
            .frame(width: 112)

            Spacer(minLength: 0)

            HoldButton(
                title: "LIFT",
                systemImage: "arrow.up.to.line",
                tint: .thrusterBlue,
                diameter: 68,
                enabled: sim.air > 0,
                isPressed: $game.controls.lift
            )
            HoldButton(
                title: "BOOST",
                systemImage: "flame.fill",
                tint: .orange,
                diameter: 84,
                enabled: sim.air > 0,
                isPressed: $game.controls.boost
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(colors: [Color(white: 0.14), Color.dashPanel], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Color.roadsterRed).frame(height: 2)
        }
    }
}
