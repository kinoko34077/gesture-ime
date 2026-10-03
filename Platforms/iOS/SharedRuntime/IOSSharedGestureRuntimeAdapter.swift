import Foundation

#if canImport(GestureIMECoreShared)
import GestureIMECoreShared
#endif

/// iOS-side coordinate/lifecycle adapter for the platform-neutral Rust gesture runtime.
///
/// This layer deliberately does not own gesture semantics. It only translates native
/// touch geometry/timestamps into the generated UniFFI API. Profile, BindingTrie,
/// Direction8, stage commits, cancellation, and ActionInvocation resolution stay in Rust.
public final class IOSSharedGestureRuntimeAdapter {
    private let core: SharedCoreRuntime

    public init(profileJSON: String) throws {
        self.core = try SharedCoreRuntime(profileJson: profileJSON)
    }

    public var profileID: String {
        core.profileId()
    }

    public var profileRevision: String {
        core.profileRevision()
    }

    public func defaultPolicy() -> FfiGesturePolicy {
        core.defaultPolicy()
    }

    public func compileLayout(layerID: String = "base") throws -> FfiLayoutSnapshot {
        try core.compileLayout(layerId: layerID)
    }

    public func beginSession(
        layerID: String = "base",
        keyID: String,
        keyWidth: Double,
        keyHeight: Double,
        touchX: Double,
        touchY: Double,
        atMs: Int64,
        policyOverride: FfiGesturePolicy? = nil
    ) throws -> IOSSharedGestureSessionAdapter {
        let session = try core.createSession(
            layerId: layerID,
            keyId: keyID,
            profileRevision: profileRevision,
            keySize: FfiSize(width: keyWidth, height: keyHeight),
            touchDown: FfiPoint(x: touchX, y: touchY),
            atMs: atMs,
            policyOverride: policyOverride
        )
        return IOSSharedGestureSessionAdapter(core: session)
    }
}

public final class IOSSharedGestureSessionAdapter {
    private let core: SharedGestureSession

    init(core: SharedGestureSession) {
        self.core = core
    }

    public func snapshot() throws -> FfiSessionSnapshot {
        try core.snapshot()
    }

    public func move(
        x: Double,
        y: Double,
        atMs: Int64? = nil
    ) throws -> FfiSessionSnapshot {
        try core.moveTo(
            point: FfiPoint(x: x, y: y),
            atMs: atMs
        )
    }

    public func advanceTime(toMs: Int64) throws -> FfiSessionSnapshot {
        try core.advanceTime(toMs: toMs)
    }

    public func touchUp(atMs: Int64? = nil) throws -> FfiSessionSnapshot {
        try core.touchUp(atMs: atMs)
    }

    public func cancel(atMs: Int64? = nil) throws -> FfiSessionSnapshot {
        try core.cancel(atMs: atMs)
    }

    public func invalidate(atMs: Int64? = nil) throws -> FfiSessionSnapshot {
        try core.invalidate(atMs: atMs)
    }
}
