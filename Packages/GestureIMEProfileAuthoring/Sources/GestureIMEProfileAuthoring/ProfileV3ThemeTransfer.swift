import Foundation

/// Theme-only transfer payload for restoring Design settings independently
/// from Board/Action/Profile semantics.
public enum ProfileV3ThemeTransfer {
    public static let schema = "gesture-ime.theme.v1"

    public static func export(theme: [String: JSONNode]) throws -> Data {
        let object: [String: Any] = [
            "schema": schema,
            "theme": theme.mapValues(\.foundationValue)
        ]
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ProfileAuthoringError.invalidJSON("Themeを書き出せません")
        }
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    public static func parse(_ data: Data) throws -> [String: JSONNode] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schema"] as? String == schema,
              let rawTheme = object["theme"] as? [String: Any] else {
            throw ProfileAuthoringError.invalidJSON(
                "gesture-ime.theme.v1 のThemeファイルではありません"
            )
        }
        return try rawTheme.mapValues(JSONNode.init(foundation:))
    }
}

extension ProfileDocument {
    /// Replaces only the top-level Theme object. Board, Actions, states,
    /// transforms and ProductSettings remain untouched.
    public mutating func v3ReplaceThemeTokens(
        _ theme: [String: JSONNode]
    ) throws {
        let existing = try v3ThemeTokens()
        for key in existing.keys {
            try v3SetThemeToken(key, value: nil)
        }
        for key in theme.keys.sorted() {
            try v3SetThemeToken(key, value: theme[key])
        }
    }
}
