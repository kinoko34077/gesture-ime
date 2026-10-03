import Foundation

@main
struct ProductProfileSharedRuntimeSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("usage: ProductProfileSharedRuntimeSmoke <profile-json>")
        }

        let profileJSON = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )
        let runtime = try IOSSharedGestureRuntimeAdapter(profileJSON: profileJSON)

        guard runtime.profileID == "builtin.ja.product" else {
            fatalError("unexpected profile id: \(runtime.profileID)")
        }

        let expectedLayers = ["base", "numbers", "alpha", "symbols"]
        for layerID in expectedLayers {
            let layout = try runtime.compileLayout(layerID: layerID)
            guard layout.keys.count == 20 else {
                fatalError("\(layerID): expected 20 keys, got \(layout.keys.count)")
            }
        }

        let base = try runtime.compileLayout(layerID: "base")
        let ids = Set(base.keys.map(\.id))
        for required in ["kana.a", "edit.delete", "text.space", "text.enter", "mode.symbols", "mode.numbers", "mode.alpha"] {
            guard ids.contains(required) else {
                fatalError("base layout missing \(required)")
            }
        }

        print("Shared Swift product Profile smoke PASS")
    }
}
