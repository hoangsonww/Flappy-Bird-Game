import UIKit

/// Thin wrapper over UIKit feedback generators.
///
/// Generators are created once and `prepare()`d, because allocating one at the
/// moment of impact adds noticeable latency.
final class Haptics {
    static let shared = Haptics()

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    /// Mirrors the player's setting; checked on every call so toggling is instant.
    var isEnabled: Bool { Settings.shared.hapticsEnabled }

    private init() {}

    /// Warm up the Taptic Engine ahead of a burst of feedback.
    func prepare() {
        guard isEnabled else { return }
        light.prepare()
        medium.prepare()
    }

    func flap() {
        guard isEnabled else { return }
        light.impactOccurred(intensity: 0.55)
    }

    func coin() {
        guard isEnabled else { return }
        selection.selectionChanged()
    }

    func powerUp() {
        guard isEnabled else { return }
        medium.impactOccurred(intensity: 0.8)
    }

    func crash() {
        guard isEnabled else { return }
        heavy.impactOccurred()
        notification.notificationOccurred(.error)
    }

    func achievement() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
    }

    func buttonTap() {
        guard isEnabled else { return }
        selection.selectionChanged()
    }
}
