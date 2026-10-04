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
    private let profileJSON: String

    public init(profileJSON: String) throws {
        self.core = try ProfileV3PlatformRuntime(profileJson: profileJSON)
        self.profileJSON = profileJSON
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

    /// Layer ID → authored display name from the Profile JSON.
    public func layerDisplayNames() -> [String: String] {
        guard let data = profileJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let layers = object["layers"] as? [[String: Any]] else {
            return [:]
        }
        var names: [String: String] = [:]
        for layer in layers {
            if let id = layer["id"] as? String, let name = layer["name"] as? String {
                names[id] = name
            }
        }
        return names
    }

    public func updateHostFacts(_ facts: IOSHostInputFacts) throws {
        try core.updateHostFacts(
            returnKey: facts.returnKey,
            keyboardType: facts.keyboardType,
            autocapitalizeNext: facts.autocapitalizeNext,
            needsInputModeSwitchKey: facts.needsInputModeSwitchKey
        )
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
        sourceVisualX: Double? = nil,
        sourceVisualY: Double? = nil,
        atMs: Int64
    ) throws -> IOSProfileV3SessionAdapter {
        // #69 §4.3: the source key's canonical rendered center is the Stage 1
        // visual origin; the physical touch-down stays the pointer origin.
        let sourceVisualOrigin = sourceVisualX.flatMap { x in
            sourceVisualY.map { y in FfiPoint(x: x, y: y) }
        }
        let session = try core.beginSessionAtVisualOrigin(
            entryId: entryID,
            logicalCellSize: FfiSize(
                width: logicalCellWidth,
                height: logicalCellHeight
            ),
            touchDown: FfiPoint(x: touchX, y: touchY),
            sourceVisualOrigin: sourceVisualOrigin,
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


/// Candidate presentation state (#69 §7). Pure presentation: it never owns or
/// mutates converter/composition state, so expanding/closing keeps composition.
public struct IOSCandidatePanelState: Equatable {
    public private(set) var expanded = false

    public init() {}

    public enum Event: Equatable {
        case toggle(candidateCount: Int)
        case close
        case candidatesChanged(count: Int)
        case candidateSelected
    }

    public mutating func apply(_ event: Event) {
        switch event {
        case .toggle(let count):
            expanded = count > 0 ? !expanded : false
        case .close, .candidateSelected:
            expanded = false
        case .candidatesChanged(let count):
            if count == 0 { expanded = false }
        }
    }
}

/// Platform-normalized host input facts (#69 §14). UIKit trait values are
/// mapped to the shared runtime's closed vocabulary by the Keyboard Extension;
/// this type and its autocapitalization rule stay Foundation-only so the
/// committed Swift smoke can exercise them.
public struct IOSHostInputFacts: Equatable {
    public var returnKey: String
    public var keyboardType: String
    public var autocapitalizeNext: Bool
    public var needsInputModeSwitchKey: Bool

    public init(
        returnKey: String = "default",
        keyboardType: String = "default",
        autocapitalizeNext: Bool = false,
        needsInputModeSwitchKey: Bool = true
    ) {
        self.returnKey = returnKey
        self.keyboardType = keyboardType
        self.autocapitalizeNext = autocapitalizeNext
        self.needsInputModeSwitchKey = needsInputModeSwitchKey
    }

    /// `mode` is one of none | words | sentences | allCharacters.
    public static func autocapitalizeNext(mode: String, textBefore: String?) -> Bool {
        let before = textBefore ?? ""
        switch mode {
        case "allCharacters":
            return true
        case "words":
            guard let last = before.last else { return true }
            return last.isWhitespace
        case "sentences":
            let trimmed = before.reversed().drop { $0 == " " || $0 == "\u{3000}" }
            guard let last = trimmed.first else { return true }
            if last.isNewline { return true }
            // Require a space after the terminator, as system keyboards do.
            guard before.last == " " else { return false }
            return ".!?。！？".contains(last)
        default:
            return false
        }
    }
}
