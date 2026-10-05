import Foundation
import Testing
@testable import GestureIMEProfileAuthoring

@Test
func themeTransferRoundTripsAndReplacesOnlyTheme() throws {
    let source: [String: JSONNode] = [
        "keyboardBackground": .string("#11223344"),
        "cornerRadius": .integer(12),
        "guideOpacity": .decimal(0.7)
    ]
    let data = try ProfileV3ThemeTransfer.export(theme: source)
    let parsed = try ProfileV3ThemeTransfer.parse(data)
    #expect(parsed == source)

    var document = try ProfileDocument.emptyV3(
        id: "user.theme.transfer",
        name: "Theme Transfer"
    )
    try document.v3SetThemeToken("obsolete", value: .string("x"))
    try document.v3ReplaceThemeTokens(parsed)

    #expect(try document.v3ThemeTokens() == source)
    #expect(document.summary.id == "user.theme.transfer")
    #expect(document.summary.name == "Theme Transfer")
}

@Test
func themeTransferRejectsWrongSchemaWithoutMutation() throws {
    let data = try JSONSerialization.data(withJSONObject: [
        "schema": "gesture-ime.theme.v0",
        "theme": ["keyboardBackground": "#FFFFFF"]
    ])
    #expect(throws: ProfileAuthoringError.self) {
        _ = try ProfileV3ThemeTransfer.parse(data)
    }
}
