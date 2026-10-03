import Foundation
import GestureIMECore

final class GestureTuningStore {
    private enum Key {
        static let deadZone = "gesture.deadZone"
        static let stage1 = "gesture.stage1"
        static let stage2 = "gesture.stage2"
        static let hysteresis = "gesture.hysteresis"
    }

    private let defaults: UserDefaults

    private(set) var deadZone: Double
    private(set) var stage1Distance: Double
    private(set) var stage2Distance: Double
    private(set) var hysteresis: Double

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        deadZone = Self.value(defaults, Key.deadZone, fallback: 0.15)
        stage1Distance = Self.value(defaults, Key.stage1, fallback: 0.40)
        stage2Distance = Self.value(defaults, Key.stage2, fallback: 0.40)
        hysteresis = Self.value(defaults, Key.hysteresis, fallback: 8.0)
        normalize()
    }

    var policy: GesturePolicy {
        GesturePolicy(
            deadZone: deadZone,
            stage1CommitDistance: max(stage1Distance, deadZone),
            stage2CommitDistance: max(stage2Distance, deadZone),
            angularHysteresisDegrees: hysteresis,
            maxDirectionalStages: 2
        )
    }

    func setDeadZone(_ value: Double) {
        deadZone = min(max(value, 0.05), 0.50)
        stage1Distance = max(stage1Distance, deadZone)
        stage2Distance = max(stage2Distance, deadZone)
        persist()
    }

    func setStage1(_ value: Double) {
        stage1Distance = min(max(value, deadZone), 1.20)
        persist()
    }

    func setStage2(_ value: Double) {
        stage2Distance = min(max(value, deadZone), 1.50)
        persist()
    }

    func setHysteresis(_ value: Double) {
        hysteresis = min(max(value, 0), 30)
        persist()
    }

    func reset() {
        deadZone = 0.15
        stage1Distance = 0.40
        stage2Distance = 0.40
        hysteresis = 8.0
        persist()
    }

    private func normalize() {
        deadZone = min(max(deadZone, 0.05), 0.50)
        stage1Distance = min(max(stage1Distance, deadZone), 1.20)
        stage2Distance = min(max(stage2Distance, deadZone), 1.50)
        hysteresis = min(max(hysteresis, 0), 30)
    }

    private func persist() {
        defaults.set(deadZone, forKey: Key.deadZone)
        defaults.set(stage1Distance, forKey: Key.stage1)
        defaults.set(stage2Distance, forKey: Key.stage2)
        defaults.set(hysteresis, forKey: Key.hysteresis)
    }

    private static func value(_ defaults: UserDefaults, _ key: String, fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }
}
