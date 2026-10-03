import Foundation
import GestureIMECore

enum BuiltInProfileLoader {
    static func load() throws -> ProfileBundle {
        guard let url = Bundle.main.url(forResource: "default-ja", withExtension: "json") else {
            throw ProfileValidationError(.missingReference, "default-ja.json")
        }
        return try ProfileCodec.decodeAndValidate(Data(contentsOf: url))
    }
}
