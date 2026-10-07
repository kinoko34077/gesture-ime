import Foundation

/// Presentation-only policy for the rebuilt Main App Edit workspace.
/// It owns no Profile/runtime semantics.
public enum ProfileV3ProductEditLayoutMode: Equatable, Sendable {
    case stacked
    case sideBySide
}

public struct ProfileV3ProductEditLayout: Equatable, Sendable {
    public let mode: ProfileV3ProductEditLayoutMode
    public let canvasExtent: Double
    public let inspectorExtent: Double

    public init(
        mode: ProfileV3ProductEditLayoutMode,
        canvasExtent: Double,
        inspectorExtent: Double
    ) {
        self.mode = mode
        self.canvasExtent = canvasExtent
        self.inspectorExtent = inspectorExtent
    }
}

public enum ProfileV3ProductEditLayoutPolicy {
    public static let wideThreshold = 680.0
    public static let wideInspectorRange = 300.0...360.0
    public static let wideInspectorFraction = 0.36

    public static let portraitCanvasRange = 180.0...280.0
    public static let portraitCanvasFraction = 0.38

    public static let shortHeightThreshold = 500.0
    public static let shortCanvasRange = 112.0...160.0
    public static let shortCanvasFraction = 0.30

    public static func resolve(
        width: Double,
        height: Double
    ) -> ProfileV3ProductEditLayout {
        let w = max(0, width)
        let h = max(0, height)

        if w >= wideThreshold {
            let inspector = min(
                max(w * wideInspectorFraction, wideInspectorRange.lowerBound),
                min(wideInspectorRange.upperBound, w)
            )
            return ProfileV3ProductEditLayout(
                mode: .sideBySide,
                canvasExtent: max(0, w - inspector),
                inspectorExtent: inspector
            )
        }

        let desired: Double
        let range: ClosedRange<Double>
        if h < shortHeightThreshold {
            desired = h * shortCanvasFraction
            range = shortCanvasRange
        } else {
            desired = h * portraitCanvasFraction
            range = portraitCanvasRange
        }

        let canvas = min(max(desired, range.lowerBound), min(range.upperBound, h))
        return ProfileV3ProductEditLayout(
            mode: .stacked,
            canvasExtent: canvas,
            inspectorExtent: max(0, h - canvas)
        )
    }
}

public struct ProfileV3EditNavigationFrame: Equatable, Sendable {
    public let sourceBoardID: String
    public let sourceEntryID: String
    public let destinationBoardID: String

    public init(
        sourceBoardID: String,
        sourceEntryID: String,
        destinationBoardID: String
    ) {
        self.sourceBoardID = sourceBoardID
        self.sourceEntryID = sourceEntryID
        self.destinationBoardID = destinationBoardID
    }
}

/// Transient Main-App-only navigation state.
/// Profile Board topology remains owned by the existing Profile/runtime model.
public struct ProfileV3EditNavigationState: Equatable, Sendable {
    public private(set) var frames: [ProfileV3EditNavigationFrame] = []

    public init() {}

    public var depth: Int { frames.count + 1 }
    public var canGoBack: Bool { !frames.isEmpty }

    public mutating func push(
        sourceBoardID: String,
        sourceEntryID: String,
        destinationBoardID: String
    ) {
        frames.append(
            ProfileV3EditNavigationFrame(
                sourceBoardID: sourceBoardID,
                sourceEntryID: sourceEntryID,
                destinationBoardID: destinationBoardID
            )
        )
    }

    @discardableResult
    public mutating func pop() -> ProfileV3EditNavigationFrame? {
        frames.popLast()
    }

    public mutating func reset() {
        frames.removeAll(keepingCapacity: true)
    }
}
