import UIKit

@MainActor
final class Haptics {
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()

    func prepare() {
        heavy.prepare()
        light.prepare()
        notify.prepare()
    }

    func countdown() {
        light.impactOccurred()
    }

    func ignition() {
        heavy.impactOccurred(intensity: 1)
    }

    func landed(_ grade: LandingGrade) {
        switch grade {
        case .greased: notify.notificationOccurred(.success)
        case .clean: heavy.impactOccurred()
        case .sketchy: notify.notificationOccurred(.warning)
        }
    }

    func outOfFuel() {
        notify.notificationOccurred(.error)
    }
}
