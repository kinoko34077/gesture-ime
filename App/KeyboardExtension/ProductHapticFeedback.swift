import UIKit
import GestureIMEProductSettings

@MainActor
final class ProductHapticFeedback {
    private let strength: CGFloat
    private let generator: UIImpactFeedbackGenerator?
    private let keySound: Bool

    init(settings: ProductSettingsValues) {
        strength = CGFloat(settings.hapticStrength)
        generator = settings.hapticsEnabled
            ? UIImpactFeedbackGenerator(style: .medium)
            : nil
        keySound = settings.keySoundEnabled

        // Prime while the keyboard is visible, rather than immediately before
        // the event. After each impact we prime again for the next accepted
        // key event.
        generator?.prepare()
    }

    /// Accepted key event (direct press, committed selection, rollback pop):
    /// #95 F8 input click plus independent haptic feedback.
    func emitCommittedSelection() {
        if keySound {
            UIDevice.current.playInputClick()
        }
        guard let generator, strength > 0 else { return }
        generator.impactOccurred(intensity: strength)
        generator.prepare()
    }
}
