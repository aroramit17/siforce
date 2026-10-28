import SwiftUI

struct TitleView: View {
    @Environment(GameController.self) private var game

    var body: some View {
        @Bindable var game = game
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROADSTER")
                        .font(.poster(46))
                        .foregroundStyle(Color.roadsterRed)
                    Text("STUNT COACH")
                        .font(.poster(34))
                        .foregroundStyle(.white)
                    Text("Unofficial. Uninsured. Briefly airborne.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                Text("Recreate the reveal: drive the loop upside down on suction fans, jump five parked vehicles on cold-gas thrusters, and stick the landing. Every stunt files an insurance claim.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if game.tiltAvailable {
                    Toggle(isOn: $game.useTilt) {
                        Label("Steer in the air by tilting the phone", systemImage: "iphone.radiowaves.left.and.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .tint(.roadsterRed)
                }
                if game.bestScore > 0 {
                    Text("Personal worst: \(Money.format(game.bestScore)) in claims")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Button("LAUNCH") { game.newRun() }
                    .buttonStyle(BigButtonStyle())
            }
            .frame(maxWidth: 340)

            ScrollView {
                FlightManual()
                    .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

/// How to fly the thing.
struct FlightManual: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("THE COURSE") {
                step("1", "Runway", "Hold THROTTLE. BOOST lights the rear thrusters: the reveal claimed 0–60 in 0.81 s, and you can beat it.")
                step("2", "The Loop", "A 28 m loop you drive upside down. Without enough speed, only the suction fan keeps you on the ceiling. Watch GRIP.")
                step("3", "The Kicker", "Full throttle up the ramp. It throws you over five parked vehicles.")
                step("4", "The Landing", "Tilt to match the landing ramp's slope and fire LIFT to soften the touchdown.")
            }
            section("CONTROLS") {
                control("bolt.car.fill", .green, "THROTTLE", "Hold to drive. Grip limits how hard the tires can push.")
                control("fanblades.fill", .fanTeal, "SUCTION FAN", "Toggle. Takes half a second to spool. Pulls up to 2 g, adds drag, and overheats after about 4 s. Overheat and it shuts off until it cools.")
                control("flame.fill", .orange, "BOOST", "Hold. Rear cold-gas thrusters. Shares the air tanks with LIFT: about 4 s of firing in total.")
                control("arrow.up.to.line", .thrusterBlue, "LIFT", "Hold, in the air. Underbody thrusters push the car up, whichever way it's pointing.")
                control("arrow.triangle.2.circlepath", .white, "TILT", "In the air, turn the phone like a steering wheel to rotate the car. Full turns before landing count as flips.")
            }
            section("LANDING LIMITS") {
                Text("Within 25° of the surface and under 9 m/s into it. Greased under 3.5 m/s. Anything else is a claim.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Based on the October 2026 reveal at a rocket test site in Texas: suction fans held the car upside down on a curved ramp, and cold-gas thrusters fed by carbon-fibre air tanks flew it over a row of parked vehicles to a soft landing. There was no driver. Not affiliated with any car company, rocket company or insurer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.heavy))
                .tracking(2)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func step(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.form(13, weight: .heavy))
                .frame(width: 22, height: 22)
                .background(Color.roadsterRed, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func control(_ systemImage: String, _ tint: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.form(13, weight: .heavy))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
