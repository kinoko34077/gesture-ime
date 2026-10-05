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
            let reader = try ProductSettingsReader(rootURL: sharedContainerRootURL)
            return try reader.readLastKnownGood()?.values ?? .defaults
        } catch {
            return .defaults
        }
    }
}
