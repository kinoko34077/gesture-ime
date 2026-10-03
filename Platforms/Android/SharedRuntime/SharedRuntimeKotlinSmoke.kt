package net.kinotch.gestureime.shared

import java.io.File

object SharedRuntimeKotlinSmoke {
    @JvmStatic
    fun main(args: Array<String>) {
        require(args.size == 1) {
            "usage: SharedRuntimeKotlinSmoke <profile-json>"
        }

        val runtime = AndroidSharedGestureRuntimeAdapter(
            File(args[0]).readText(),
        )
        check(runtime.profileId == "fixture.diagonal-two-stage") {
            "unexpected profile id: ${runtime.profileId}"
        }

        val layout = runtime.compileLayout()
        check(layout.keys.size == 1 && layout.keys[0].id == "kana.a") {
            "shared layout snapshot mismatch"
        }

        val session = runtime.beginSession(
            keyId = "kana.a",
            keyWidth = 100.0,
            keyHeight = 100.0,
            touchX = 0.0,
            touchY = 0.0,
            atMs = 0L,
        )

        check(session.move(40.0, 0.0).path.size == 1) {
            "stage 1 path was not committed"
        }
        check(session.move(80.0, 0.0).path.size == 2) {
            "stage 2 path was not committed"
        }

        val finalState = session.touchUp()
        check(
            finalState.dispatchedActions.size == 1 &&
                finalState.dispatchedActions[0].actionId == "cursor.move",
        ) {
            "shared action dispatch mismatch"
        }

        println("Shared Kotlin adapter smoke PASS")
    }
}
