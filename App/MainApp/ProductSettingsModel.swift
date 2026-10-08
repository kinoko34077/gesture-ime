import Foundation
import Combine
import CoreHaptics
import UIKit
import GestureIMEProductSettings

@MainActor
final class ProductSettingsModel: ObservableObject {
    @Published private(set) var values: ProductSettingsValues = .defaults
    @Published private(set) var deliveryCapability: ProductSettingsDeliveryCapability = .appLocalOnly
    @Published var errorMessage: String?
    @Published private(set) var hapticTestStatus: String?
    @Published private(set) var probe: ProductSettingsCapabilityProbe.Result =
        .unavailable(.appGroupNotConfigured)

    private var reader: ProductSettingsReader?
    private var writer: ProductSettingsWriter?
    private let keySoundCapability = ProductKeySoundCapability()

    init() {
        let probe = ProductSettingsCapabilityProbe.probeMainBundle()
        self.probe = probe
        deliveryCapability = probe.capability
        do {
            let root = try probe.rootURL ?? Self.appLocalRootURL()
            let reader = try ProductSettingsReader(rootURL: root)
            let writer = try ProductSettingsWriter(rootURL: root)
            self.reader = reader
            self.writer = writer

            if let snapshot = try reader.readLastKnownGood() {
                values = snapshot.values
            } else {
                _ = try writer.publish(values)
            }
        } catch {
            errorMessage = error.localizedDescription
            values = .defaults
        }
    }

    /// #69 §13: a setting is effective or visibly unavailable with a reason.
    var isEditable: Bool { deliveryCapability.crossProcessAvailable }

    var keySoundEditable: Bool {
        isEditable && keySoundCapability.isAvailable
    }

    var effectiveKeySoundEnabled: Bool {
        keySoundCapability.effectiveEnabled(
            storedEnabled: values.keySoundEnabled
        )
    }

    var keySoundStatus: String {
        keySoundCapability.japaneseReason
    }

    var deliveryStatus: String {
        switch probe {
        case .available:
            "キーボード本体へ反映されます（次にキーボードを開いた時）。"
        case .unavailable(let reason):
            reason.japaneseReason
        }
    }

    /// Test the Main App's feedback path only. A successful request does not
    /// prove output from the separate Keyboard Extension process.
    func testHaptic() {
        guard values.hapticStrength > 0 else {
            hapticTestStatus = "触覚はオフです。強さを上げてから試してください。"
            return
        }

        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            hapticTestStatus = "この端末は触覚フィードバックに対応していません。"
            return
        }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(
            intensity: CGFloat(values.hapticStrength)
        )

        hapticTestStatus = isEditable
            ? "アプリから触覚の発生を要求しました。キーボード本体での振動は別に確認してください。"
            : "アプリから触覚の発生を要求しました。キーボード本体への設定反映は利用できません。"
    }

    func clearHapticTestStatus() {
        hapticTestStatus = nil
    }

    func setHapticStrength(_ value: Double) {
        guard isEditable else { return }
        hapticTestStatus = nil
        persist(
            hapticStrength: min(1, max(0, value)),
            keyboardHeightScale:
                values.keyboardHeightScale
        )
    }

    func setKeyboardHeightScale(_ value: Double) {
        guard isEditable,
              value.isFinite,
              value > 0 else {
            return
        }

        persist(
            hapticStrength: values.hapticStrength,
            keyboardHeightScale: value
        )
    }

    func reset() {
        hapticTestStatus = nil
        persist(
            hapticStrength: ProductSettingsValues.defaults.hapticStrength,
            keyboardHeightScale: ProductSettingsValues.defaults.keyboardHeightScale,
            keySoundEnabled: ProductSettingsValues.defaults.keySoundEnabled
        )
    }

    func setKeySound(_ enabled: Bool) {
        guard keySoundEditable else { return }
        persist(
            hapticStrength: values.hapticStrength,
            keyboardHeightScale: values.keyboardHeightScale,
            keySoundEnabled: enabled
        )
    }

    private func persist(
        hapticStrength: Double,
        keyboardHeightScale: Double,
        keySoundEnabled: Bool? = nil
    ) {
        do {
            let next = try ProductSettingsValues(
                hapticStrength: hapticStrength,
                keyboardHeightScale: keyboardHeightScale,
                keySoundEnabled: keySoundEnabled ?? values.keySoundEnabled
            )
            guard let writer else {
                values = next
                return
            }
            _ = try writer.publish(next)
            values = next
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func appLocalRootURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base
            .appendingPathComponent("GestureIME", isDirectory: true)
            .appendingPathComponent("ProductSettings", isDirectory: true)
    }
}
