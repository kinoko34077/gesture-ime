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
    }

    /// Accepted key event (direct press, committed selection, rollback pop):
    /// #93 / #95 §F8 input click, then haptics. Audibility follows the iOS
    /// 「キーボードのクリック」 setting.
    func emitCommittedSelection() {
        if keySound {
            UIDevice.current.playInputClick()
        }
        guard let generator, strength > 0 else { return }
        generator.prepare()
        generator.impactOccurred(intensity: strength)
    }
}
