import UIKit

@MainActor
final class Haptics {
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()

    func prepare() {
        heavy.prepare()
        rigid.prepare()
        light.prepare()
        notify.prepare()
    }

    func click() {
        rigid.impactOccurred(intensity: 0.6)
    }

    /// A buzz while thrusters fire; call it every few hundredths of a second.
    func rumble(_ intensity: Double) {
        light.impactOccurred(intensity: CGFloat(max(0.2, min(1, intensity))))
    }

    func thump() {
        heavy.impactOccurred(intensity: 1)
    }

    func success() {
        notify.notificationOccurred(.success)
    }

    func warning() {
        notify.notificationOccurred(.warning)
    }

    func crash() {
        notify.notificationOccurred(.error)
        heavy.impactOccurred(intensity: 1)
    }
}
