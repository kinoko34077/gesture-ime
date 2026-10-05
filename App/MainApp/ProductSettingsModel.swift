import Foundation
import Combine
import GestureIMEProductSettings

@MainActor
final class ProductSettingsModel: ObservableObject {
    @Published private(set) var values: ProductSettingsValues = .defaults
    @Published private(set) var deliveryCapability: ProductSettingsDeliveryCapability = .appLocalOnly
    @Published var errorMessage: String?
    @Published private(set) var probe: ProductSettingsCapabilityProbe.Result =
        .unavailable(.appGroupNotConfigured)

    private var reader: ProductSettingsReader?
    private var writer: ProductSettingsWriter?
    private let keySoundCapability =
        ProductKeySoundCapability(hasFullAccess: false)

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

    func incrementHaptic() {
        persist(
            hapticStrength: min(1.0, values.hapticStrength + 0.1),
            keyboardHeightScale: values.keyboardHeightScale
        )
    }

    func decrementHaptic() {
        persist(
            hapticStrength: max(0.0, values.hapticStrength - 0.1),
            keyboardHeightScale: values.keyboardHeightScale
        )
    }

    func incrementHeightScale() {
        persist(
            hapticStrength: values.hapticStrength,
            keyboardHeightScale: values.keyboardHeightScale + 0.05
        )
    }

    func decrementHeightScale() {
        let next = values.keyboardHeightScale - 0.05
        guard next > 0 else { return }
        persist(
            hapticStrength: values.hapticStrength,
            keyboardHeightScale: next
        )
    }

    func reset() {
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
