package net.kinotch.gestureime.shared

import java.io.File
import uniffi.gesture_ime_core.FfiBoardCoordinate
import uniffi.gesture_ime_core.FfiPoint

object SharedRuntimeKotlinSmoke {
    @JvmStatic
    fun main(args: Array<String>) {
        require(args.size == 1) {
            "usage: SharedRuntimeKotlinSmoke <profile-json>"
        }

        val runtime = AndroidSharedGestureRuntimeAdapter(
            File(args[0]).readText(),
        )

        when (runtime.profileId) {
            "fixture.diagonal-two-stage" -> runLegacyCompatibility(runtime)
            "fixture.v2.chain" -> runBoardGraphV2(runtime)
            else -> error("unexpected profile id: ${runtime.profileId}")
        }

        println("Shared Kotlin adapter smoke PASS: ${runtime.profileId}")
    }

    private fun runLegacyCompatibility(runtime: AndroidSharedGestureRuntimeAdapter) {
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

        val first = session.move(40.0, 0.0)
        check(first.path.size == 1 && first.boardTransitionCount == 1L) {
            "v1 stage 1 was not normalized into a Board transition"
        }
        val boardState = session.boardState()
        check(
            boardState.currentBoardId != boardState.persistentBoardId &&
                boardState.committedCoordinates.size == 1,
        ) {
            "v1 compatibility Board state mismatch"
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
    }

    private fun runBoardGraphV2(runtime: AndroidSharedGestureRuntimeAdapter) {
        val layout = runtime.compileLayout()
        check(layout.keys.size == 1 && layout.keys[0].id == "key.test") {
            "v2 layout snapshot mismatch"
        }

        val session = runtime.beginSession(
            keyId = "key.test",
            keyWidth = 100.0,
            keyHeight = 100.0,
            touchX = 0.0,
            touchY = 0.0,
            atMs = 0L,
        )

        val first = session.move(50.0, 0.0, 10L)
        check(
            first.currentBoardId == "board.e" &&
                first.persistentBoardId == "board.root" &&
                first.boardTransitionCount == 1L &&
                first.anchor == FfiPoint(50.0, 0.0),
        ) {
            "v2 Board transition/local-origin reset mismatch"
        }

        val second = session.move(50.0, -50.0, 20L)
        check(second.selectedCoordinate == FfiBoardCoordinate(0L, -1L)) {
            "v2 local-coordinate selection mismatch"
        }

        val finalState = session.touchUp(30L)
        check(
            finalState.currentBoardId == "board.root" &&
                finalState.dispatchedActions.size == 1 &&
                finalState.dispatchedActions[0].actionId == "text.insert",
        ) {
            "v2 transient baseline/action mismatch"
        }
    }
}
