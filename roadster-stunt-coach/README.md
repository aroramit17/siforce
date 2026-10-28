# Roadster Stunt Coach

A parody iPhone game that recreates the October 2026 Roadster reveal: a car drives a loop upside down on suction fans, jumps a row of parked vehicles on cold-gas thrusters, and lands softly. You fly it from a cockpit with throttle, a suction fan switch, two thruster banks, and a dashboard of gauges. Every stunt files a fake insurance claim.

Unofficial and unaffiliated with any car company, rocket company or insurer.

## What the reveal showed (and what the game models)

| At the reveal | In the game |
|---|---|
| Underbody fans pulled air from under the car, enough suction (reported up to ~2 g) to hold it upside down on a curved ramp | **SUCTION FAN** switch: spools up in 0.5 s, adds up to 2 g of grip and some drag, overheats after ~4 s and shuts off until it cools |
| Cold-gas thrusters fed by carbon-fibre air tanks (COPVs) | **BOOST** (rear thrusters) and **LIFT** (underbody thrusters) share one **COPV AIR** tank: about 4 s of firing in total |
| Claimed 0–60 mph in about 0.81 s | A 0–60 timer. Full boost from the line does it in 0.79 s |
| Launched off a ramp, cleared five parked vehicles, flipped in the air | A kicker ramp, five parked vehicles, and tilt-to-rotate in the air. Full turns count as flips |
| Thrusters softened the landing | Land within 25° of the surface and under 9 m/s into it, or it's a crash |
| No one was in the car | Crash claims are denied: "There was no driver. The car filed this claim itself." |

## The course

```
 START ── runway ──(  LOOP  )── flat ── kicker ╱   Sedan Crossover Truck Robotaxi Semi   ╲ LAND HERE ── runout
                   28 m tall                   25°                                      ╲ 12° landing ramp
```

1. **Runway (22 m).** Hold THROTTLE. The motor is grip- and power-limited, so it alone can't carry you through the loop.
2. **The Loop (14 m radius).** On the ceiling you stay on only if speed plus suction beats gravity. Watch the GRIP gauge. Fan on from just before the loop until past the top works. Fan off before the top drops you. Fan on the whole run overheats it. Burning about 0.6 s of BOOST on the runway also gets you through, at the cost of air.
3. **Kicker (25°).** Full throttle up the ramp. It throws you over the lineup at ~30 m/s.
4. **Air.** Turn the phone like a steering wheel to rotate the car (or use the on-screen rotate buttons). Match the landing ramp's −12° slope. Fire LIFT on the way down to soften the touchdown.
5. **Landing.** Under 3.5 m/s is greased.

## Cockpit

- **Left:** SUCTION FAN switch (with OFF / SPOOLING / SEALED / OVERHEAT light) and the THROTTLE pedal.
- **Middle:** SPEED and COPV AIR dials, plus FAN RPM, FAN TEMP, GRIP (in g) and ALT bars.
- **Right:** LIFT and BOOST. You can hold several at once.
- **Top:** caution lights (GRIP LOW, INVERTED, FAN HOT, LOW AIR, BOOST, LIFT) and the 0–60 timer against the reveal's 0.81 s.
- **Coach:** shouts what to do next ("Loop ahead! FAN ON or BOOST!", "Nose down!", "LIFT! Soften the landing!").

## Claims and score

| Claim | Base | Graded by |
|---|---|---|
| The Launch | $5,000 | 0–60 time: under 0.81 s is greased |
| The Loop | $12,000 | Greased if you cut it within 1 g of falling off |
| The Five-Car Hop | $4,000 per vehicle | All five is greased |
| The Backflip / Frontflip | $15,000 / $18,000 per flip | Landing |
| The Thruster Landing | $10,000 | Impact speed |
| Totaled | $250,000 | Always denied, never scored |

Grades multiply the claim: greased ×1.5, clean ×1, sketchy ×0.6. Your score is the total of your stunt claims, and your best is saved as your "personal worst".

## Build and run

Requires Xcode 16 or later and iOS 17 or later. The game runs in landscape.

1. Open `RoadsterStuntCoach.xcodeproj`.
2. Select the **RoadsterStuntCoach** target → *Signing & Capabilities*, pick your team, and change the bundle identifier from `com.example.RoadsterStuntCoach` to one you own.
3. Run on an iPhone. The Simulator works too, but it has no gyro, so it shows NOSE UP / NOSE DN buttons instead of tilt steering. Tilt steering can also be turned off on the title screen.

If the project won't open in your Xcode version, regenerate it from `project.yml`:

```bash
brew install xcodegen
```

```bash
xcodegen
```

## Tests

The physics, scoring and claims are plain Swift with no UIKit or CoreMotion, so they also build as a Swift package. The tests fly scripted pilots through the course: throttle-only falls off the loop, the fan or a boost gets through, the fan left on overheats, full boost beats 0.81 s, landing nose-up crashes, coasting from the loop top hits the Semi, and a backflip with a lift burn lands.

```bash
swift test
```

## Layout

```
RoadsterStuntCoach/
  App/RoadsterStuntCoachApp.swift   App entry and phase switching
  App/GameController.swift          Frame loop (fixed 120 Hz sim steps), tilt, haptics, camera, crash paperwork, report
  App/FrameDriver.swift             CADisplayLink wrapper
  App/Haptics.swift                 Thruster rumble, landing and crash feedback
  Motion/TiltSensor.swift           Device gravity → steering-wheel angle
  Core/                             Pure game rules, shared with Package.swift
    Course.swift                    Loop, kicker, parked vehicles, landing ramp geometry
    LaunchSim.swift                 Car physics: grip, suction, motor, thrusters, flight, landing, crashes
    Coach.swift                     Tilt steering math and the coach's lines
    Stunt.swift                     Stunt kinds, grades, and turning a finished run into stunts
    InsuranceAdjuster.swift         Seeded claim generator and all the paperwork copy
    ClaimsReport.swift              Score, ranks, share text, money formatting
  Views/
    CourseCanvas.swift              Side-view renderer: sky, test stand, loop, kicker, lineup, ramp, car, plumes
    CockpitView.swift               Course + HUD + dashboard
    CockpitControls.swift           Dial and bar gauges, caution lights, hold buttons, fan switch
    TitleView.swift                 Title and flight manual
    ClaimsReportView.swift          The claims report
Tests/StuntCoreTests/               XCTest suite for Core
```

### Physics, briefly

On the track the car's load into the surface is `v²/r + g·cos θ + suction`. If it drops below zero on the loop, the car falls. Motor traction is capped by `grip × load`, and above ~10 m/s by power (`90 / v` m/s²). Thrusters push along the car's axes regardless of grip. In the air it's a point mass with drag, plus a rotation rate you control. All the numbers live in `Tuning`. They were tuned against a scripted prototype so each system matters.
