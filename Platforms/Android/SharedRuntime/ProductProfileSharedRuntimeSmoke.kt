package net.kinotch.gestureime.shared

import java.io.File

object ProductProfileSharedRuntimeSmoke {
    @JvmStatic
    fun main(args: Array<String>) {
        require(args.size == 1) {
            "usage: ProductProfileSharedRuntimeSmoke <profile-json>"
        }

        val runtime = AndroidSharedGestureRuntimeAdapter(
            File(args[0]).readText(),
        )
        check(runtime.profileId == "builtin.ja.product") {
            "unexpected profile id: ${runtime.profileId}"
        }

        listOf("base", "numbers", "alpha", "symbols").forEach { layerId ->
            val layout = runtime.compileLayout(layerId)
            check(layout.keys.size == 20) {
                "$layerId: expected 20 keys, got ${layout.keys.size}"
            }
        }

        val baseIds = runtime.compileLayout("base").keys.map { it.id }.toSet()
        listOf(
            "kana.a",
            "edit.delete",
            "text.space",
            "text.enter",
            "mode.symbols",
            "mode.numbers",
            "mode.alpha",
        ).forEach { required ->
            check(required in baseIds) {
                "base layout missing $required"
            }
        }

        println("Shared Kotlin product Profile smoke PASS")
    }
}
