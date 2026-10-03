import XCTest
@testable import GestureIMECore

final class BuiltInKeyboardProfileTests: XCTestCase {
    func testPhase3BuiltInProfileValidAndGestureGrammarIsDataDriven() throws {
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

        let profile = try ProfileCodec.decodeAndValidate(Data(contentsOf: url))
        let layer = try XCTUnwrap(profile.layers.first(where: { $0.id == "base" }))
        let bindingSet = try XCTUnwrap(profile.bindingSets.first(where: { $0.id == layer.bindingSetRef }))

        let ordinary = try BindingTrieCompiler.compile(bindingSet, keyID: "kana.a")
        XCTAssertEqual(ordinary.root.eligibleDirections, Set([.w, .n, .e, .s]))

        let experimental = try BindingTrieCompiler.compile(bindingSet, keyID: "test.gesture")
        XCTAssertEqual(experimental.root.eligibleDirections, Set([.ne, .e]))

        let eastNode = try XCTUnwrap(
            experimental.node(for: GesturePath([GestureToken(direction: .e)]))
        )
        XCTAssertEqual(eastNode.eligibleDirections, Set([.n]))

        for placement in profile.layouts.flatMap(\.placements) {
            _ = try BindingTrieCompiler.compile(bindingSet, keyID: placement.keyID)
        }
    }
}
