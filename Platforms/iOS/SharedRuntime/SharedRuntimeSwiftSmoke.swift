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
        guard runtime.profileID == "fixture.diagonal-two-stage" else {
            fatalError("unexpected profile id: \(runtime.profileID)")
        }

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
        guard stage1.path.count == 1 else {
            fatalError("stage 1 path was not committed")
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

        print("Shared Swift adapter smoke PASS")
    }
}
