import Foundation

#if canImport(GestureIMECoreShared)
import GestureIMECoreShared
#endif

/// iOS-side coordinate/lifecycle adapter for the platform-neutral Rust input runtime.
///
/// This layer deliberately does not own input semantics. It only translates native
/// touch geometry/timestamps into the generated UniFFI API. Profile validation,
/// v1-to-v2 normalization, Board selection/transition lifetime, cancellation, and
/// ActionInvocation resolution stay in Rust.
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


public struct IOSBoardSessionState {
    public let currentBoardID: String
    public let persistentBoardID: String
    public let eligibleCoordinates: [FfiBoardCoordinate]
    public let candidateCoordinate: FfiBoardCoordinate?
    public let selectedCoordinate: FfiBoardCoordinate?
    public let committedCoordinates: [FfiBoardCoordinate]
    public let transitionCount: Int64
    public let transitionLimitHit: Bool

    init(snapshot: FfiSessionSnapshot) {
        currentBoardID = snapshot.currentBoardId
        persistentBoardID = snapshot.persistentBoardId
        eligibleCoordinates = snapshot.eligibleCoordinates
        candidateCoordinate = snapshot.candidateCoordinate
        selectedCoordinate = snapshot.selectedCoordinate
        committedCoordinates = snapshot.committedCoordinates
        transitionCount = snapshot.boardTransitionCount
        transitionLimitHit = snapshot.transitionLimitHit
    }
}

public extension IOSSharedGestureSessionAdapter {
    func boardState() throws -> IOSBoardSessionState {
        IOSBoardSessionState(snapshot: try snapshot())
    }
}


/// iOS transport adapter for the Profile v3 product runtime.
///
/// This is intentionally separate from IOSSharedGestureRuntimeAdapter while the
/// built-in Profile remains on the v1/v2 staging path. Board geometry, endpoint
/// resolution, transition state and runtime-dispatch ordering remain owned by Rust.
public final class IOSProfileV3RuntimeAdapter {
    private let core: ProfileV3PlatformRuntime

    public init(profileJSON: String) throws {
        self.core = try ProfileV3PlatformRuntime(profileJson: profileJSON)
    }

    public var profileID: String {
        core.profileId()
    }

    public var profileRevision: String {
        core.profileRevision()
    }

    public func activeLayerID() throws -> String {
        try core.activeLayerId()
    }

    public func defaultPolicy() -> FfiProfileV3GesturePolicy {
        core.defaultPolicy()
    }

    public func updateSemanticContext(
        composition: String,
        conversionActive: Bool,
        conversionHasCandidates: Bool
    ) throws {
        try core.updateSemanticContext(
            composition: composition,
            conversionActive: conversionActive,
            conversionHasCandidates: conversionHasCandidates
        )
    }

    public func directSurface() throws -> FfiProfileV3BoardSurface {
        try core.directSurface()
    }

    public func previewSurface(boardID: String) throws -> FfiProfileV3BoardSurface {
        try core.previewSurface(boardId: boardID)
    }

    public func setLayer(_ layerID: String) throws -> FfiProfileV3BoardSurface {
        try core.setLayer(layerId: layerID)
    }

    public func pushLayer(_ layerID: String) throws -> FfiProfileV3BoardSurface {
        try core.pushLayer(layerId: layerID)
    }

    public func popLayer() throws -> FfiProfileV3BoardSurface {
        try core.popLayer()
    }

    public func beginSession(
        entryID: String,
        logicalCellWidth: Double,
        logicalCellHeight: Double,
        touchX: Double,
        touchY: Double,
        atMs: Int64
    ) throws -> IOSProfileV3SessionAdapter {
        let session = try core.beginSession(
            entryId: entryID,
            logicalCellSize: FfiSize(
                width: logicalCellWidth,
                height: logicalCellHeight
            ),
            touchDown: FfiPoint(x: touchX, y: touchY),
            atMs: atMs
        )
        return IOSProfileV3SessionAdapter(core: session)
    }
}

public final class IOSProfileV3SessionAdapter {
    private let core: ProfileV3PlatformSession

    init(core: ProfileV3PlatformSession) {
        self.core = core
    }

    public func snapshot() throws -> FfiProfileV3SessionSnapshot {
        try core.snapshot()
    }

    public func move(
        x: Double,
        y: Double,
        atMs: Int64? = nil
    ) throws -> FfiProfileV3SessionSnapshot {
        try core.moveTo(
            point: FfiPoint(x: x, y: y),
            atMs: atMs
        )
    }

    public func advanceTime(toMs: Int64) throws -> FfiProfileV3SessionSnapshot {
        try core.advanceTime(toMs: toMs)
    }

    public func touchUp(atMs: Int64? = nil) throws -> FfiProfileV3SessionSnapshot {
        try core.touchUp(atMs: atMs)
    }

    public func cancel(atMs: Int64? = nil) throws -> FfiProfileV3SessionSnapshot {
        try core.cancel(atMs: atMs)
    }

    public func invalidate(atMs: Int64? = nil) throws -> FfiProfileV3SessionSnapshot {
        try core.invalidate(atMs: atMs)
    }
}


/// Numeric projection shared by the committed Swift smoke and the actual v3
/// product renderer. It maps authored atomic Board coordinates into one concrete
/// rendered surface without introducing a second semantic layout.
public struct IOSProfileV3MappedFrame: Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func contains(x pointX: Double, y pointY: Double) -> Bool {
        pointX >= x
            && pointX < x + width
            && pointY >= y
            && pointY < y + height
    }
}

public struct IOSProfileV3BoardGeometryMapping {
    public let minX: Int64
    public let minY: Int64
    public let maxX: Int64
    public let maxY: Int64
    public let atomicWidth: Double
    public let atomicHeight: Double

    public init?(
        surface: FfiProfileV3BoardSurface,
        width: Double,
        height: Double
    ) {
        guard let bounds = surface.bounds else { return nil }

        let atomicColumns = bounds.maxX - bounds.minX
        let atomicRows = bounds.maxY - bounds.minY
        guard atomicColumns > 0,
              atomicRows > 0,
              width > 0,
              height > 0 else {
            return nil
        }

        minX = bounds.minX
        minY = bounds.minY
        maxX = bounds.maxX
        maxY = bounds.maxY
        atomicWidth = width / Double(atomicColumns)
        atomicHeight = height / Double(atomicRows)
    }

    public var logicalCellWidth: Double { atomicWidth * 2 }
    public var logicalCellHeight: Double { atomicHeight * 2 }

    public func frame(for rect: FfiProfileV3Rect) -> IOSProfileV3MappedFrame {
        IOSProfileV3MappedFrame(
            x: Double(rect.x - minX) * atomicWidth,
            y: Double(rect.y - minY) * atomicHeight,
            width: Double(rect.width) * atomicWidth,
            height: Double(rect.height) * atomicHeight
        )
    }

    public func relativeFrame(
        for rect: FfiProfileV3Rect,
        anchorX: Double,
        anchorY: Double
    ) -> IOSProfileV3MappedFrame {
        IOSProfileV3MappedFrame(
            x: anchorX + Double(rect.x) * atomicWidth,
            y: anchorY + Double(rect.y) * atomicHeight,
            width: Double(rect.width) * atomicWidth,
            height: Double(rect.height) * atomicHeight
        )
    }
}
