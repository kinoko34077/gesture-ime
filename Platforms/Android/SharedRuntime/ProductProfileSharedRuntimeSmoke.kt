package net.kinotch.gestureime.shared

import java.io.File
import uniffi.gesture_ime_core.ProfileV3PlatformRuntime

object ProductProfileSharedRuntimeSmoke {
    @JvmStatic
    fun main(args: Array<String>) {
        require(args.size == 1) {
            "usage: ProductProfileSharedRuntimeSmoke <profile-json>"
        }

        val runtime = ProfileV3PlatformRuntime(
            File(args[0]).readText(),
        )
        check(runtime.profileId() == "builtin.ja.product") {
            "unexpected profile id: ${runtime.profileId()}"
        }

        val expectedLayers = linkedMapOf(
            "layer.ja" to "board.ja.root",
            "layer.numbers" to "board.numbers.root",
            "layer.alpha" to "board.alpha.root",
            "layer.symbols" to "board.symbols.root",
        )

        expectedLayers.forEach { (layerId, boardId) ->
            val surface = runtime.setLayer(layerId)
            check(surface.layerId == layerId) {
                "$layerId: unexpected layer ${surface.layerId}"
            }
            check(surface.boardId == boardId) {
                "$layerId: expected $boardId, got ${surface.boardId}"
            }
            check(surface.entries.isNotEmpty()) {
                "$layerId: expected authored v3 entries"
            }
        }

        println("Shared Kotlin v3 product Profile smoke PASS")
    }
}
