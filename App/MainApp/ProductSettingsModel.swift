import Foundation
import Combine
import GestureIMEProductSettings

@MainActor
final class ProductSettingsModel: ObservableObject {
    @Published private(set) var values: ProductSettingsValues = .defaults
    @Published private(set) var deliveryCapability: ProductSettingsDeliveryCapability = .appLocalOnly
    @Published var errorMessage: String?

    private var store: ProductSettingsStore?

    init() {
        do {
            let root = try Self.appLocalRootURL()
            let store = try ProductSettingsStore(rootURL: root)
            self.store = store

            if let snapshot = try store.readLastKnownGood() {
                values = snapshot.values
            } else {
                _ = try store.publish(values)
            }
        } catch {
            errorMessage = error.localizedDescription
            values = .defaults
        }
    }

    var deliveryStatus: String {
        switch deliveryCapability {
        case .sharedContainer:
            "キーボード本体へ反映されます。"
        case .appLocalOnly:
            "このアプリ内のみ。署名済みの共有領域が確認できないため、キーボード本体には反映されません。"
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
            keyboardHeightScale: ProductSettingsValues.defaults.keyboardHeightScale
        )
    }

    private func persist(
        hapticStrength: Double,
        keyboardHeightScale: Double
    ) {
        do {
            let next = try ProductSettingsValues(
                hapticStrength: hapticStrength,
                keyboardHeightScale: keyboardHeightScale
            )
            guard let store else {
                values = next
                return
            }
            _ = try store.publish(next)
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
