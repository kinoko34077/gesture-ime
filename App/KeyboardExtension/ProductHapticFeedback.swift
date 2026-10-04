import UIKit
import GestureIMEProductSettings

@MainActor
final class ProductHapticFeedback {
    private let strength: CGFloat
    private let generator: UIImpactFeedbackGenerator?

    init(settings: ProductSettingsValues) {
        strength = CGFloat(settings.hapticStrength)
        generator = settings.hapticsEnabled
            ? UIImpactFeedbackGenerator(style: .medium)
            : nil
    }

    func emitCommittedSelection() {
        guard let generator, strength > 0 else { return }
        generator.prepare()
        generator.impactOccurred(intensity: strength)
    }
}
