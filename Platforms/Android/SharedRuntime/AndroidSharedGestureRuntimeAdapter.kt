package net.kinotch.gestureime.shared

import uniffi.gesture_ime_core.FfiGesturePolicy
import uniffi.gesture_ime_core.FfiLayoutSnapshot
import uniffi.gesture_ime_core.FfiPoint
import uniffi.gesture_ime_core.FfiSessionSnapshot
import uniffi.gesture_ime_core.FfiSize
import uniffi.gesture_ime_core.SharedCoreRuntime
import uniffi.gesture_ime_core.SharedGestureSession

/**
 * Android-side coordinate/lifecycle adapter for the platform-neutral Rust gesture runtime.
 *
 * Gesture/Profile/Binding semantics remain in Rust. This layer only translates native
 * pointer geometry/timestamps into the generated UniFFI API.
 */
class AndroidSharedGestureRuntimeAdapter(
    profileJson: String,
) {
    private val core = SharedCoreRuntime(profileJson)

    val profileId: String
        get() = core.profileId()

    val profileRevision: String
        get() = core.profileRevision()

    fun defaultPolicy(): FfiGesturePolicy = core.defaultPolicy()

    fun compileLayout(layerId: String = "base"): FfiLayoutSnapshot =
        core.compileLayout(layerId)

    fun beginSession(
        layerId: String = "base",
        keyId: String,
        keyWidth: Double,
        keyHeight: Double,
        touchX: Double,
        touchY: Double,
        atMs: Long,
        policyOverride: FfiGesturePolicy? = null,
    ): AndroidSharedGestureSessionAdapter {
        val session = core.createSession(
            layerId,
            keyId,
            profileRevision,
            FfiSize(keyWidth, keyHeight),
            FfiPoint(touchX, touchY),
            atMs,
            policyOverride,
        )
        return AndroidSharedGestureSessionAdapter(session)
    }
}

class AndroidSharedGestureSessionAdapter internal constructor(
    private val core: SharedGestureSession,
) {
    fun snapshot(): FfiSessionSnapshot = core.snapshot()

    fun move(
        x: Double,
        y: Double,
        atMs: Long? = null,
    ): FfiSessionSnapshot = core.moveTo(FfiPoint(x, y), atMs)

    fun advanceTime(toMs: Long): FfiSessionSnapshot = core.advanceTime(toMs)

    fun touchUp(atMs: Long? = null): FfiSessionSnapshot = core.touchUp(atMs)

    fun cancel(atMs: Long? = null): FfiSessionSnapshot = core.cancel(atMs)

    fun invalidate(atMs: Long? = null): FfiSessionSnapshot = core.invalidate(atMs)
}
