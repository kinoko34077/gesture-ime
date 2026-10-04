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
        let runtime = try IOSProfileV3RuntimeAdapter(profileJSON: profileJSON)

        guard runtime.profileID == "builtin.ja.product" else {
            fatalError("unexpected profile id: \(runtime.profileID)")
        }

        let expectedLayers: [(String, String)] = [
            ("layer.ja", "board.ja.root"),
            ("layer.numbers", "board.numbers.root"),
            ("layer.alpha", "board.alpha.root"),
            ("layer.symbols", "board.symbols.root"),
        ]

        for (layerID, boardID) in expectedLayers {
            let surface = try runtime.setLayer(layerID)
            guard surface.layerId == layerID else {
                fatalError("\(layerID): unexpected layer \(surface.layerId)")
            }
            guard surface.boardId == boardID else {
                fatalError("\(layerID): expected \(boardID), got \(surface.boardId)")
            }
            guard !surface.entries.isEmpty else {
                fatalError("\(layerID): expected authored v3 entries")
            }
        }

        print("Shared Swift v3 product Profile smoke PASS")
    }
}
