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
}
