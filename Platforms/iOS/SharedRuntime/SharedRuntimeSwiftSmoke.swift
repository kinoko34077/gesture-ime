import Foundation

@main
struct SharedRuntimeSwiftSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("usage: SharedRuntimeSwiftSmoke <profile-json>")
        }

        let profileJSON = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )

        if profileSchema(profileJSON) == "gesture-ime.profile.v3" {
            let runtime = try IOSProfileV3RuntimeAdapter(profileJSON: profileJSON)
            guard runtime.profileID == "profile.v3.a3.product-smoke" else {
                fatalError("unexpected v3 profile id: \(runtime.profileID)")
            }
            try runProfileV3ProductSurface(runtime)
            print("Shared Swift v3 adapter smoke PASS: \(runtime.profileID)")
            return
        }

        let runtime = try IOSSharedGestureRuntimeAdapter(profileJSON: profileJSON)

        switch runtime.profileID {
        case "fixture.diagonal-two-stage":
            try runLegacyCompatibility(runtime)
        case "fixture.v2.chain":
            try runBoardGraphV2(runtime)
        default:
            fatalError("unexpected profile id: \(runtime.profileID)")
        }

        print("Shared Swift adapter smoke PASS: \(runtime.profileID)")
    }

    private static func profileSchema(_ profileJSON: String) -> String? {
        guard let data = profileJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary["schema"] as? String
    }

    private static func runProfileV3ProductSurface(
        _ runtime: IOSProfileV3RuntimeAdapter
    ) throws {
        let direct = try runtime.directSurface()
        guard direct.layerId == "layer.base",
              direct.boardId == "board.root",
              direct.entries.count == 3 else {
            fatalError("v3 direct Board surface mismatch")
        }
        try verifyProfileV3Geometry(direct)
        try runtime.updateSemanticContext(
            composition: "か",
            conversionActive: true,
            conversionHasCandidates: true
        )
        let converted = try runtime.directSurface()
        guard converted.entries.first(where: { $0.id == "key.return" })?.text == "確定" else {
            fatalError("v3 conditional presentation mismatch")
        }

        let flick = try runtime.beginSession(
            entryID: "key.flick",
            logicalCellWidth: 100,
            logicalCellHeight: 50,
            touchX: 0,
            touchY: 0,
            atMs: 0
        )
        let initial = try flick.snapshot()
        guard initial.currentBoardId == "board.flick",
              initial.context == .relative,
              initial.surface.entries.contains(where: { $0.id == "flick.ne" }),
              initial.surface.entries.contains(where: { $0.id == "flick.far-east" }) else {
            fatalError("v3 relative surface mismatch")
        }
        try verifyProfileV3RelativeGeometry(direct: direct, relative: initial)
        let diagonal = try flick.move(x: 60, y: -30, atMs: 10)
        guard diagonal.currentEndpointEntryId == "flick.ne" else {
            fatalError("v3 diagonal selection mismatch")
        }

        try runtime.updateSemanticContext(
            composition: "か",
            conversionActive: false,
            conversionHasCandidates: false
        )
        let transform = try runtime.beginSession(
            entryID: "key.dakuten",
            logicalCellWidth: 100,
            logicalCellHeight: 50,
            touchX: 0,
            touchY: 0,
            atMs: 0
        )
        let final = try transform.touchUp(atMs: 10)
        guard final.runtimeDispatches.count == 1,
              final.runtimeDispatches[0].matchedSource == "か",
              final.runtimeDispatches[0].replacement == "が" else {
            fatalError("v3 transform dispatch mismatch")
        }
    }

    private static func runLegacyCompatibility(
        _ runtime: IOSSharedGestureRuntimeAdapter
    ) throws {
        let layout = try runtime.compileLayout()
        guard layout.keys.count == 1, layout.keys[0].id == "kana.a" else {
            fatalError("shared layout snapshot mismatch")
        }

        let session = try runtime.beginSession(
            keyID: "kana.a",
            keyWidth: 100,
            keyHeight: 100,
            touchX: 0,
            touchY: 0,
            atMs: 0
        )

        let stage1 = try session.move(x: 40, y: 0)
        guard stage1.path.count == 1,
              stage1.boardTransitionCount == 1 else {
            fatalError("v1 stage 1 was not normalized into a Board transition")
        }

        let boardState = try session.boardState()
        guard boardState.currentBoardID != boardState.persistentBoardID,
              boardState.committedCoordinates.count == 1 else {
            fatalError("v1 compatibility Board state mismatch")
        }

        let stage2 = try session.move(x: 80, y: 0)
        guard stage2.path.count == 2 else {
            fatalError("stage 2 path was not committed")
        }

        let final = try session.touchUp()
        guard final.dispatchedActions.count == 1,
              final.dispatchedActions[0].actionId == "cursor.move" else {
            fatalError("shared action dispatch mismatch")
        }
    }

    private static func runBoardGraphV2(
        _ runtime: IOSSharedGestureRuntimeAdapter
    ) throws {
        let layout = try runtime.compileLayout()
        guard layout.keys.count == 1, layout.keys[0].id == "key.test" else {
            fatalError("v2 layout snapshot mismatch")
        }

        let session = try runtime.beginSession(
            keyID: "key.test",
            keyWidth: 100,
            keyHeight: 100,
            touchX: 0,
            touchY: 0,
            atMs: 0
        )

        let first = try session.move(x: 50, y: 0, atMs: 10)
        guard first.currentBoardId == "board.e",
              first.persistentBoardId == "board.root",
              first.boardTransitionCount == 1,
              abs(first.anchor.x - 50) < 0.0001,
              abs(first.anchor.y) < 0.0001 else {
            fatalError("v2 Board transition/local-origin reset mismatch")
        }

        let second = try session.move(x: 50, y: -50, atMs: 20)
        guard let selected = second.selectedCoordinate,
              selected.x == 0,
              selected.y == -1 else {
            fatalError("v2 local-coordinate selection mismatch")
        }

        let final = try session.touchUp(atMs: 30)
        guard final.currentBoardId == "board.root",
              final.dispatchedActions.count == 1,
              final.dispatchedActions[0].actionId == "text.insert" else {
            fatalError("v2 transient baseline/action mismatch")
        }
    }
}


private func verifyProfileV3Geometry(
    _ direct: FfiProfileV3BoardSurface
) throws {
    guard let mapping = IOSProfileV3BoardGeometryMapping(
        surface: direct,
        width: 240,
        height: 40
    ) else {
        throw NSError(domain: "A3Geometry", code: 1)
    }

    guard abs(mapping.logicalCellWidth - 40) < 0.0001,
          abs(mapping.logicalCellHeight - 40) < 0.0001 else {
        throw NSError(domain: "A3Geometry", code: 2)
    }

    let frames = Dictionary(
        uniqueKeysWithValues: direct.entries.map {
            ($0.id, mapping.frame(for: $0.rect))
        }
    )

    guard frames["key.flick"]
            == IOSProfileV3MappedFrame(x: 0, y: 0, width: 80, height: 40),
          frames["key.return"]
            == IOSProfileV3MappedFrame(x: 80, y: 0, width: 80, height: 40),
          frames["key.dakuten"]
            == IOSProfileV3MappedFrame(x: 200, y: 0, width: 40, height: 40) else {
        throw NSError(domain: "A3Geometry", code: 3)
    }

    guard !frames.values.contains(where: { $0.contains(x: 180, y: 20) }) else {
        throw NSError(domain: "A3Geometry", code: 4)
    }
}


private func verifyProfileV3RelativeGeometry(
    direct: FfiProfileV3BoardSurface,
    relative: FfiProfileV3SessionSnapshot
) throws {
    guard let mapping = IOSProfileV3BoardGeometryMapping(
        surface: direct,
        width: 240,
        height: 40
    ),
    let diagonal = relative.surface.entries.first(where: { $0.id == "flick.ne" })
    else {
        throw NSError(domain: "A3RelativeGeometry", code: 1)
    }

    let frame = mapping.relativeFrame(
        for: diagonal.rect,
        anchorX: 100,
        anchorY: 100
    )
    guard frame == IOSProfileV3MappedFrame(
        x: 120,
        y: 40,
        width: 40,
        height: 40
    ) else {
        throw NSError(domain: "A3RelativeGeometry", code: 2)
    }
}
