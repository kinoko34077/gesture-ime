import Foundation
import GestureIMEProfileAuthoring
import GestureIMEProductSettings

struct KeyboardResolvedConfiguration: Equatable {
    let profileJSON: String
    let profileGeneration: UInt64?
    let productSettings: ProductSettingsValues
    let productSettingsGeneration: UInt64?
}

struct KeyboardSharedConfigurationSource {
    let paths: GestureIMEAppGroupPaths?

    init(
        result: GestureIMEAppGroupResolver.Result =
            GestureIMEAppGroupResolver.resolveMainBundle()
    ) {
        paths = result.paths
    }

    func load() throws -> KeyboardResolvedConfiguration {
        var profileJSON = try BuiltInProfileLoader.loadJSON()
        var profileGeneration: UInt64?
        var productSettings = ProductSettingsValues.defaults
        var productSettingsGeneration: UInt64?

        if let paths {
            do {
                let reader = try ActiveProfileSnapshotReader(
                    rootURL: paths.profileDeliveryRootURL,
                    validator: Self.validateProfile
                )
                if let snapshot = try reader.readLastKnownGood(),
                   let sharedJSON = String(data: snapshot.data, encoding: .utf8) {
                    profileJSON = sharedJSON
                    profileGeneration = snapshot.manifest.generation
                }
            } catch {
                // Shared Profile failure is fail-closed to bundled product data.
            }

            do {
                let reader = try ProductSettingsReader(
                    rootURL: paths.productSettingsRootURL
                )
                if let snapshot = try reader.readLastKnownGood() {
                    productSettings = snapshot.values
                    productSettingsGeneration = snapshot.manifest.generation
                }
            } catch {
                // ProductSettings are independently fail-closed to defaults.
            }
        }

        return KeyboardResolvedConfiguration(
            profileJSON: profileJSON,
            profileGeneration: profileGeneration,
            productSettings: productSettings,
            productSettingsGeneration: productSettingsGeneration
        )
    }

    private static func validateProfile(_ data: Data) -> ProfileValidation {
        guard let json = String(data: data, encoding: .utf8) else {
            return ProfileValidation(
                valid: false,
                errorCode: "E_INVALID_JSON",
                detail: "Profile is not UTF-8"
            )
        }

        let result = validateProfileJson(profileJson: json)
        return ProfileValidation(
            valid: result.valid,
            errorCode: result.errorCode,
            detail: result.detail
        )
    }
}
