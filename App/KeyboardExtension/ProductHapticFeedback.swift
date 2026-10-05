import UIKit
import GestureIMEProductSettings

@MainActor
final class ProductHapticFeedback {
    private let strength: CGFloat
    private let generator: UIImpactFeedbackGenerator?
    private let keySound: Bool

    init(
        settings: ProductSettingsValues,
        keySoundCapability: ProductKeySoundCapability
    ) {
        strength = CGFloat(settings.hapticStrength)
        generator = settings.hapticsEnabled
            ? UIImpactFeedbackGenerator(style: .medium)
            : nil
        keySound = keySoundCapability.effectiveEnabled(
            storedEnabled: settings.keySoundEnabled
        )
    }

    /// Accepted key event (direct press, committed selection, rollback pop):
    /// #93 / #95 §F8 input click, then haptics. Input-click audio is emitted
    /// only when the keyboard actually has Full Access; haptics are independent.
    func emitCommittedSelection() {
        if keySound {
            UIDevice.current.playInputClick()
        }
        guard let generator, strength > 0 else { return }
        generator.prepare()
        generator.impactOccurred(intensity: strength)
    }
}
