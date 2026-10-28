import QuartzCore
import UIKit

/// Calls back once per screen refresh with the seconds since the previous frame.
@MainActor
final class FrameDriver: NSObject {
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private let onFrame: @MainActor (Double) -> Void

    init(onFrame: @escaping @MainActor (Double) -> Void) {
        self.onFrame = onFrame
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Must be called to release the driver: the display link holds on to its target.
    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let last = lastTimestamp else { return }
        onFrame(link.timestamp - last)
    }
}
