import Foundation
import GestureIMEProfileAuthoring

enum SharedRuntimeProfileValidator {
    static func validate(_ data: Data) -> ProfileValidation {
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

    static func migrateToV2(_ data: Data) throws -> Data {
        guard let json = String(data: data, encoding: .utf8) else {
            throw ProfileAuthoringError.invalidJSON("Profile is not UTF-8")
        }
        let migrated = try migrateProfileToV2Json(profileJson: json)
        guard let data = migrated.data(using: .utf8) else {
            throw ProfileAuthoringError.invalidJSON("Migrated Profile is not UTF-8")
        }
        return data
    }
}
