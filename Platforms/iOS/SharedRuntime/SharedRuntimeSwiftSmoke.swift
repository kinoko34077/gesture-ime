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
              first.anchor == FfiPoint(x: 50, y: 0) else {
            fatalError("v2 Board transition/local-origin reset mismatch")
        }

        let second = try session.move(x: 50, y: -50, atMs: 20)
        guard second.selectedCoordinate == FfiBoardCoordinate(x: 0, y: -1) else {
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
