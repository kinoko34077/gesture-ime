import Foundation
import GestureIMECore

@MainActor
final class GesturePolicyStore {
    private enum Key {
        static let deadZone = "gesture.policy.deadZone"
        static let stage1 = "gesture.policy.stage1"
        static let stage2 = "gesture.policy.stage2"
        static let hysteresis = "gesture.policy.hysteresis"
    }

    private let defaults: UserDefaults
    private let fallback: GesturePolicy

    private(set) var deadZone: Double
    private(set) var stage1: Double
    private(set) var stage2: Double
    private(set) var hysteresis: Double

    init(defaultPolicy: GesturePolicy, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fallback = defaultPolicy
        deadZone = Self.value(defaults, Key.deadZone, fallback: defaultPolicy.deadZone)
        stage1 = Self.value(defaults, Key.stage1, fallback: defaultPolicy.stage1CommitDistance)
        stage2 = Self.value(defaults, Key.stage2, fallback: defaultPolicy.stage2CommitDistance)
        hysteresis = Self.value(defaults, Key.hysteresis, fallback: defaultPolicy.angularHysteresisDegrees)
        normalizeAndPersist()
    }

    var policy: GesturePolicy {
        GesturePolicy(
            deadZone: deadZone,
            stage1CommitDistance: max(stage1, deadZone),
            stage2CommitDistance: max(stage2, deadZone),
            angularHysteresisDegrees: min(max(hysteresis, 0), 44),
            maxDirectionalStages: 2
        )
    }

    func setDeadZone(_ value: Double) {
        deadZone = min(max(value, 0.02), 0.60)
        if stage1 < deadZone { stage1 = deadZone }
        if stage2 < deadZone { stage2 = deadZone }
        normalizeAndPersist()
    }

    func setStage1(_ value: Double) {
        stage1 = min(max(value, deadZone), 1.50)
        normalizeAndPersist()
    }

    func setStage2(_ value: Double) {
        stage2 = min(max(value, deadZone), 1.80)
        normalizeAndPersist()
    }

    func setHysteresis(_ value: Double) {
        hysteresis = min(max(value, 0), 30)
        normalizeAndPersist()
    }

    func resetToProfileDefaults() {
        deadZone = fallback.deadZone
        stage1 = fallback.stage1CommitDistance
        stage2 = fallback.stage2CommitDistance
        hysteresis = fallback.angularHysteresisDegrees
        normalizeAndPersist()
    }

    private func normalizeAndPersist() {
        deadZone = min(max(deadZone, 0.02), 0.60)
        stage1 = min(max(stage1, deadZone), 1.50)
        stage2 = min(max(stage2, deadZone), 1.80)
        hysteresis = min(max(hysteresis, 0), 30)

        defaults.set(deadZone, forKey: Key.deadZone)
        defaults.set(stage1, forKey: Key.stage1)
        defaults.set(stage2, forKey: Key.stage2)
        defaults.set(hysteresis, forKey: Key.hysteresis)
    }

    private static func value(_ defaults: UserDefaults, _ key: String, fallback: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.double(forKey: key)
    }
}
