import Foundation
import GestureIMEProductSettings

struct KeyboardProductSettingsSource {
    let sharedContainerRootURL: URL?

    var capability: ProductSettingsDeliveryCapability {
        sharedContainerRootURL == nil ? .appLocalOnly : .sharedContainer
    }

    func loadLastKnownGood() -> ProductSettingsValues {
        guard let sharedContainerRootURL else {
            return .defaults
        }

        do {
            let store = try ProductSettingsStore(rootURL: sharedContainerRootURL)
            return try store.readLastKnownGood()?.values ?? .defaults
        } catch {
            return .defaults
        }
    }
}
