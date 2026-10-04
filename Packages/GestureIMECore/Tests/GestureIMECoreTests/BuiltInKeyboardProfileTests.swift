import Foundation
import XCTest

final class BuiltInKeyboardProfileTests: XCTestCase {
    func testProductProfileIsCanonicalV3AndRetainsFiveColumnJapaneseRoot() throws {
        let object = try loadProductObject()
        XCTAssertEqual(object["schema"] as? String, "gesture-ime.profile.v3")
        XCTAssertEqual(object["id"] as? String, "builtin.ja.product")
        XCTAssertEqual(object["initialLayerRef"] as? String, "layer.ja")

        let layers = try XCTUnwrap(object["layers"] as? [[String: Any]])
        XCTAssertEqual(
            Set(layers.compactMap { $0["id"] as? String }),
            Set([
                "layer.ja",
                "layer.numbers",
                "layer.alpha",
                "layer.symbols",
                "layer.utility.phrase",
                "layer.utility.emoji",
                "layer.utility.emoticon"
            ])
        )

        let boards = try XCTUnwrap(object["boards"] as? [[String: Any]])
        let japanese = try XCTUnwrap(
            boards.first(where: { $0["id"] as? String == "board.ja.root" })
        )
        let entries = try XCTUnwrap(japanese["entries"] as? [[String: Any]])

        let expected: [(String, Int, Int, Int, Int)] = [
            ("mode.symbols", 0, 0, 2, 2),
            ("kana.a", 2, 0, 2, 2),
            ("kana.ka", 4, 0, 2, 2),
            ("kana.sa", 6, 0, 2, 2),
            ("edit.delete", 8, 0, 2, 2),

            ("mode.numbers", 0, 2, 2, 2),
            ("kana.ta", 2, 2, 2, 2),
            ("kana.na", 4, 2, 2, 2),
            ("kana.ha", 6, 2, 2, 2),
            ("text.space", 8, 2, 2, 2),

            ("mode.alpha", 0, 4, 2, 2),
            ("kana.ma", 2, 4, 2, 2),
            ("kana.ya", 4, 4, 2, 2),
            ("kana.ra", 6, 4, 2, 2),
            ("text.enter", 8, 4, 2, 4),

            ("kana.transform", 0, 6, 2, 2),
            ("utility.open", 2, 6, 2, 2),
            ("kana.wa", 4, 6, 2, 2),
            ("punctuation", 6, 6, 2, 2)
        ]

        XCTAssertEqual(entries.count, expected.count)
        for (id, x, y, width, height) in expected {
            let entry = try XCTUnwrap(
                entries.first(where: { $0["id"] as? String == id }),
                id
            )
            let rect = try XCTUnwrap(entry["rect"] as? [String: Any], id)
            XCTAssertEqual(rect["x"] as? Int, x, id)
            XCTAssertEqual(rect["y"] as? Int, y, id)
            XCTAssertEqual(rect["width"] as? Int, width, id)
            XCTAssertEqual(rect["height"] as? Int, height, id)
        }
    }

    func testProductProfileDeclaresTransformsShiftDiagonalAndUtilityLayers() throws {
        let object = try loadProductObject()
        let tables = try XCTUnwrap(object["transformTables"] as? [[String: Any]])
        XCTAssertEqual(
            Set(tables.compactMap { $0["id"] as? String }),
            Set(["kana.small", "kana.dakuten", "kana.handakuten", "latin.shift"])
        )

        let states = try XCTUnwrap(object["states"] as? [[String: Any]])
        let latinCase = try XCTUnwrap(
            states.first(where: { $0["id"] as? String == "latinCase" })
        )
        XCTAssertEqual(latinCase["type"] as? String, "enum")
        XCTAssertEqual(latinCase["values"] as? [String], ["lower", "upper"])
        XCTAssertEqual(latinCase["default"] as? String, "lower")

        let boards = try XCTUnwrap(object["boards"] as? [[String: Any]])
        let punctuation = try XCTUnwrap(
            boards.first(where: {
                ($0["id"] as? String)?.contains("punctuation.flick") == true
            })
        )
        let punctuationEntries = try XCTUnwrap(
            punctuation["entries"] as? [[String: Any]]
        )
        XCTAssertTrue(
            punctuationEntries.contains(where: {
                guard let rect = $0["rect"] as? [String: Any] else { return false }
                return rect["x"] as? Int == 1 && rect["y"] as? Int == -3
            })
        )

        let transformBoard = try XCTUnwrap(
            boards.first(where: { $0["id"] as? String == "board.ja.transform" })
        )
        let transformIDs = Set(
            (transformBoard["entries"] as? [[String: Any]] ?? [])
                .compactMap { $0["id"] as? String }
        )
        XCTAssertTrue(transformIDs.isSuperset(
            of: ["transform.center", "transform.small", "transform.dakuten", "transform.handakuten"]
        ))

        let data = try loadProductData()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("\"panel.open\""))
    }

    private func loadProductObject() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: loadProductData())
        return try XCTUnwrap(object as? [String: Any])
    }

    private func loadProductData() throws -> Data {
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

        return try Data(contentsOf: url)
    }
}
