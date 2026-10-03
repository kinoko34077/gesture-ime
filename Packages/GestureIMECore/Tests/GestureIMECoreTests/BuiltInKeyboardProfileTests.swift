import XCTest
@testable import GestureIMECore

final class BuiltInKeyboardProfileTests: XCTestCase {
    func testProductProfileIsValidAndMatchesFiveColumnReferenceTopology() throws {
        let profile = try loadProductProfile()
        XCTAssertEqual(profile.id, "builtin.ja.product")
        XCTAssertEqual(profile.version, 3)

        let baseLayer = try XCTUnwrap(profile.layers.first(where: { $0.id == "base" }))
        let baseLayout = try XCTUnwrap(profile.layouts.first(where: { $0.id == baseLayer.layoutRef }))
        let baseBindings = try XCTUnwrap(profile.bindingSets.first(where: { $0.id == baseLayer.bindingSetRef }))

        let expected: [(String, Int, Int, Double, Double)] = [
            ("mode.symbols", 0, 0, 2, 1),
            ("kana.a", 0, 2, 2, 1),
            ("kana.ka", 0, 4, 2, 1),
            ("kana.sa", 0, 6, 2, 1),
            ("edit.delete", 0, 8, 2, 1),

            ("mode.numbers", 1, 0, 2, 1),
            ("kana.ta", 1, 2, 2, 1),
            ("kana.na", 1, 4, 2, 1),
            ("kana.ha", 1, 6, 2, 1),
            ("text.space", 1, 8, 2, 1),

            ("mode.alpha", 2, 0, 2, 1),
            ("kana.ma", 2, 2, 2, 1),
            ("kana.ya", 2, 4, 2, 1),
            ("kana.ra", 2, 6, 2, 1),
            ("text.enter", 2, 8, 2, 2),

            ("utility.chat", 3, 0, 1, 1),
            ("utility.emoji", 3, 1, 1, 1),
            ("utility.emoticon", 3, 2, 2, 1),
            ("kana.wa", 3, 4, 2, 1),
            ("punctuation", 3, 6, 2, 1)
        ]

        XCTAssertEqual(baseLayout.placements.count, expected.count)
        for (keyID, row, column, width, height) in expected {
            let placement = try XCTUnwrap(baseLayout.placements.first(where: { $0.keyID == keyID }), keyID)
            XCTAssertEqual(placement.row, row, keyID)
            XCTAssertEqual(placement.column, column, keyID)
            XCTAssertEqual(placement.width ?? 1, width, keyID)
            XCTAssertEqual(placement.height ?? 1, height, keyID)
        }

        let ordinary = try BindingTrieCompiler.compile(baseBindings, keyID: "kana.a")
        XCTAssertEqual(ordinary.root.eligibleDirections, Set([.w, .n, .e, .s]))

        XCTAssertEqual(Set(profile.layers.map(\.id)), Set(["base", "numbers", "alpha", "symbols"]))

        for layer in profile.layers {
            let layout = try XCTUnwrap(profile.layouts.first(where: { $0.id == layer.layoutRef }), layer.id)
            let bindingSet = try XCTUnwrap(profile.bindingSets.first(where: { $0.id == layer.bindingSetRef }), layer.id)
            XCTAssertEqual(layout.placements.count, 20, layer.id)

            for placement in layout.placements {
                _ = try BindingTrieCompiler.compile(bindingSet, keyID: placement.keyID)
            }
        }
    }

    func testBaseModeKeysResolveToRealLayers() throws {
        let profile = try loadProductProfile()
        let layer = try XCTUnwrap(profile.layers.first(where: { $0.id == "base" }))
        let bindingSet = try XCTUnwrap(profile.bindingSets.first(where: { $0.id == layer.bindingSetRef }))

        let expectations: [String: String] = [
            "mode.symbols": "symbols",
            "mode.numbers": "numbers",
            "mode.alpha": "alpha"
        ]

        for (keyID, expectedLayer) in expectations {
            let trie = try BindingTrieCompiler.compile(bindingSet, keyID: keyID)
            let action = try XCTUnwrap(trie.root.behavior?.onRelease.first, keyID)
            XCTAssertEqual(action.actionID, "layer.set", keyID)
            XCTAssertEqual(action.arguments["layer"]?.stringValue, expectedLayer, keyID)
        }
    }

    private func loadProductProfile() throws -> ProfileBundle {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let url = repoRoot
            .appendingPathComponent("App")
            .appendingPathComponent("KeyboardExtension")
            .appendingPathComponent("Resources")
            .appendingPathComponent("default-ja.json")

        return try ProfileCodec.decodeAndValidate(Data(contentsOf: url))
    }
}
