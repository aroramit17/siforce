# Roadster Stunt Coach

A silly parody iPhone game inspired by the Roadster stunt reveal. Hold your phone like a tiny car, then tilt, flip and spin it to pull off stunts. You get **4 seconds of fuel**, and every stunt files a fake insurance claim.

Unofficial and unaffiliated with any car company, rocket company or insurer.

## How a run works

1. Tap **IGNITION**. A 3-second countdown gives you time to get a grip.
2. The fuel gauge starts draining: 4.00s, in real time.
3. Every stunt the motion sensors detect files a claim with a claim number, a description, an adjuster's note, a dollar amount, and a stamp: APPROVED, DENIED (with a reason) or UNDER REVIEW.
4. Clean landings refund a little fuel ("regenerative braking": +0.3s greased, +0.15s clean). Stunts landed within 1.25s of each other chain into a multiplier (+0.25× per link, capped at ×3).
5. When the tank runs dry you get the **Claims Report**: total claimed, actually paid, premium increase, your longest chain, and the coach's verdict, from *Never Left the Showroom* up to *Uninsurable*. Share it or run it back.

## Stunts

Hold the phone upright in portrait, screen facing you.

| Stunt | How | Detected as | Base claim |
|---|---|---|---|
| The Ramp | Snap the nose up past 40°, then back down | Rotation around the x axis, 40° to 300° | $1,200 |
| The Hover | Hold dead still for 1 second | Rotation < 0.25 rad/s and acceleration < 0.06 g for 1s | $9,999 |
| The Donut | Turn it 360° like a steering wheel | Rotation around z ≥ 300° | $4,200 |
| The Launch | Jolt it straight up, fast | Upward acceleration ≥ 1.1 g | $6,500 |
| The Kickflip | Roll it 360° along its long edge | Rotation around y ≥ 300° | $8,500 |
| The Backflip | Flip it end over end | Rotation around x ≥ 300° | $14,000 |
| The Double Kickflip | Two full rolls | Rotation around y ≥ 660° | $22,000 |
| The Tre Flip | Kickflip plus a half spin | y ≥ 300° and z ≥ 150° in one move | $31,000 |

Landing grades scale the claim: **Greased** ×1.5, **Clean** ×1.0, **Sketchy** ×0.6. For flips, the grade depends on how close you came to a whole number of turns. For the ramp, it depends on whether the nose came back down.

Play over a bed or a couch. The claims are fake; the cracked screen would be real.

## Build and run

Requires Xcode 16 or later and iOS 17 or later.

1. Open `RoadsterStuntCoach.xcodeproj`.
2. Select the **RoadsterStuntCoach** target → *Signing & Capabilities*, pick your team, and change the bundle identifier from `com.example.RoadsterStuntCoach` to one you own.
3. Run on a real iPhone. The Simulator has no gyro, so it shows tap-to-fake stunt buttons instead.

If the project won't open in your Xcode version, regenerate it from `project.yml`:

```bash
brew install xcodegen
```

```bash
xcodegen
```

## Tests

The game rules (stunt detection, fuel, chains, claims, ranks) are plain Swift with no UIKit or CoreMotion, so they also build as a Swift package. The tests feed scripted 100 Hz motion into the detector, so no phone or simulator is needed:

```bash
swift test
```

## Layout

```
RoadsterStuntCoach/
  App/RoadsterStuntCoachApp.swift   App entry and phase switching
  App/GameController.swift          Countdown, run loop, sensors → session, best score, coach lines
  App/Haptics.swift                 Countdown, landing and out-of-fuel haptics
  Motion/MotionEngine.swift         CoreMotion device motion at 100 Hz → MotionSample
  Core/                             Pure game rules, shared with Package.swift
    StuntDetector.swift             Gesture segmentation and stunt classification
    FuelGauge.swift                 The 4-second tank
    GameSession.swift               Chains, multipliers, refunds, filing claims
    InsuranceAdjuster.swift         Seeded claim generator and all the paperwork copy
    ClaimsReport.swift              Totals, ranks, share text, money formatting
  Views/                            Title, run, fuel gauge and claims report screens
Tests/StuntCoreTests/               XCTest suite for Core
```

### How detection works

`StuntDetector` splits motion into gestures. A gesture starts when the phone spins faster than 2.5 rad/s, integrates rotation on each axis, and ends once the phone settles below 1 rad/s for 150 ms (or after 2 seconds). The gesture is classified by its **peak** rotation per axis and graded by its **net** rotation. Snapping up into a ramp, pausing, then coming back down is counted once: an opposite-direction ramp within 0.8s of a ramp is treated as the way back down. Launches and hovers are checked on every sample. All thresholds live in `StuntDetector.Thresholds` for tuning on real hardware.
