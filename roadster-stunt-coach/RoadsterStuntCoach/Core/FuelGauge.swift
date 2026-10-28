import Foundation

/// Four seconds of fuel, burned in real time. Clean landings put a little back.
struct FuelGauge {
    static let capacity: TimeInterval = 4.0

    private(set) var remaining: TimeInterval = FuelGauge.capacity
    private var lastBurn: TimeInterval?

    var fraction: Double { remaining / Self.capacity }
    var isEmpty: Bool { remaining <= 0 }

    /// Burns fuel up to `time`. The first call only starts the clock.
    mutating func burn(to time: TimeInterval) {
        guard let last = lastBurn else {
            lastBurn = time
            return
        }
        guard time > last else { return }
        remaining = max(0, remaining - (time - last))
        lastBurn = time
    }

    /// Regenerative braking. An empty tank stays empty: the run is over.
    mutating func refund(_ seconds: TimeInterval) {
        guard !isEmpty, seconds > 0 else { return }
        remaining = min(Self.capacity, remaining + seconds)
    }
}
