import Foundation

// #100 / frozen #95 §F5 — ResizableWorkspace layout policy. Pure, point-based,
// derived only from actual usable geometry. Values in `Tuning` are the
// provisional §F5.2 defaults; the rules in `resolve` are the §F5.1 invariants.

public enum ProfileV3WorkspaceAxis: String, Sendable, Equatable {
    /// Primary above secondary.
    case vertical
    /// Primary leading, secondary trailing.
    case horizontal
}

public struct ProfileV3WorkspaceSplit: Equatable, Sendable {
    public let axis: ProfileV3WorkspaceAxis
    /// Primary pane extent along the split axis (points).
    public let primary: Double
    /// Secondary pane extent along the split axis (points).
    public let secondary: Double
    /// Primary / (primary + secondary), for persistence.
    public var ratio: Double { primary + secondary > 0 ? primary / (primary + secondary) : 0 }
}

public enum ProfileV3WorkspaceLayout {
    /// §F5.2 provisional, physically tunable values (points / ratios).
    public struct Tuning: Equatable, Sendable {
        public var aspectThreshold = 1.30
        public var shortHeight = 520.0
        public var verticalDefaultFraction = 0.36
        public var verticalDefaultRange = 180.0...280.0
        public var verticalPrimaryMin = 120.0
        public var verticalSecondaryMin = 200.0
        public var horizontalDefaultFraction = 0.42
        public var horizontalPrimaryMin = 240.0
        public var horizontalSecondaryMin = 300.0
        public var dividerThickness = 12.0
        public init() {}
    }

    /// §F5.1 rule 3. `layoutWidth/Height` exclude software-keyboard occlusion
    /// so showing the keyboard never flips the axis.
    public static func axis(
        layoutWidth: Double,
        layoutHeight: Double,
        tuning: Tuning = Tuning()
    ) -> ProfileV3WorkspaceAxis {
        guard layoutWidth > 0, layoutHeight > 0 else { return .vertical }
        return layoutWidth / layoutHeight >= tuning.aspectThreshold
            || layoutHeight < tuning.shortHeight ? .horizontal : .vertical
    }

    /// Resolves pane sizes for the *currently available* extent (which
    /// shrinks while the software keyboard is shown). `storedRatio` is the
    /// persisted editor UI state for this workspace/axis, if any.
    public static func resolve(
        layoutWidth: Double,
        layoutHeight: Double,
        availableWidth: Double,
        availableHeight: Double,
        storedRatio: Double?,
        tuning: Tuning = Tuning()
    ) -> ProfileV3WorkspaceSplit {
        let axis = axis(layoutWidth: layoutWidth, layoutHeight: layoutHeight, tuning: tuning)
        let extent = axis == .vertical ? availableHeight : availableWidth
        let total = max(0, extent - tuning.dividerThickness)
        let (primaryMin, secondaryMin): (Double, Double) = axis == .vertical
            ? (tuning.verticalPrimaryMin, tuning.verticalSecondaryMin)
            : (tuning.horizontalPrimaryMin, tuning.horizontalSecondaryMin)

        let desired: Double
        if let storedRatio, storedRatio.isFinite, storedRatio > 0, storedRatio < 1 {
            desired = storedRatio * total
        } else if axis == .vertical {
            let base = tuning.verticalDefaultFraction * (layoutHeight - tuning.dividerThickness)
            desired = min(max(base, tuning.verticalDefaultRange.lowerBound), tuning.verticalDefaultRange.upperBound)
        } else {
            desired = tuning.horizontalDefaultFraction * total
        }

        let primary: Double
        if total >= primaryMin + secondaryMin {
            primary = min(max(desired, primaryMin), total - secondaryMin)
        } else {
            // §F5.1 rule 7: the secondary (inspector) pane wins.
            primary = max(0, min(primaryMin, total - min(secondaryMin, total)))
        }
        return ProfileV3WorkspaceSplit(axis: axis, primary: primary, secondary: total - primary)
    }
}


public enum ProfileV3WorkspacePriority: String, CaseIterable, Sendable, Equatable {
    case canvas
    case inspector
}

public enum ProfileV3PriorityWorkspaceMode: String, Sendable, Equatable {
    case stacked
    case sideBySide
}

public struct ProfileV3PriorityWorkspaceSplit: Equatable, Sendable {
    public let mode: ProfileV3PriorityWorkspaceMode
    public let priority: ProfileV3WorkspacePriority
    public let canvas: Double
    public let inspector: Double

    public init(
        mode: ProfileV3PriorityWorkspaceMode,
        priority: ProfileV3WorkspacePriority,
        canvas: Double,
        inspector: Double
    ) {
        self.mode = mode
        self.priority = priority
        self.canvas = canvas
        self.inspector = inspector
    }
}

/// #157 P13 / U2: Board/Edit workspace policy.
///
/// Phone/compact geometry has exactly two user states and no ratio input:
/// Canvas priority and Inspector priority. Wide geometry is side-by-side only
/// when both panes can retain their minimum working widths.
public enum ProfileV3PriorityWorkspaceLayout {
    public struct Tuning: Equatable, Sendable {
        public var canvasPriorityInspectorFraction = 0.34
        public var canvasPriorityInspectorRange = 176.0...240.0
        public var inspectorPriorityCanvasFraction = 0.28
        public var inspectorPriorityCanvasRange = 144.0...220.0

        public var wideCanvasMin = 360.0
        public var wideInspectorMin = 280.0
        public var wideInspectorFraction = 0.34
        public var wideInspectorRange = 300.0...360.0
        public var wideSeparatorAllowance = 1.0

        public init() {}
    }

    public static func resolve(
        availableWidth: Double,
        availableHeight: Double,
        priority: ProfileV3WorkspacePriority,
        tuning: Tuning = Tuning()
    ) -> ProfileV3PriorityWorkspaceSplit {
        let width = max(0, availableWidth)
        let height = max(0, availableHeight)

        let wideThreshold =
            tuning.wideCanvasMin
            + tuning.wideInspectorMin
            + tuning.wideSeparatorAllowance

        if width >= wideThreshold {
            let desiredInspector = min(
                max(
                    tuning.wideInspectorFraction * width,
                    tuning.wideInspectorRange.lowerBound
                ),
                tuning.wideInspectorRange.upperBound
            )
            let maximumInspector = max(0, width - tuning.wideCanvasMin)
            let inspector = min(desiredInspector, maximumInspector)
            return ProfileV3PriorityWorkspaceSplit(
                mode: .sideBySide,
                priority: priority,
                canvas: width - inspector,
                inspector: inspector
            )
        }

        switch priority {
        case .canvas:
            let desiredInspector = min(
                max(
                    tuning.canvasPriorityInspectorFraction * height,
                    tuning.canvasPriorityInspectorRange.lowerBound
                ),
                tuning.canvasPriorityInspectorRange.upperBound
            )
            let inspector = min(height, desiredInspector)
            return ProfileV3PriorityWorkspaceSplit(
                mode: .stacked,
                priority: .canvas,
                canvas: max(0, height - inspector),
                inspector: inspector
            )

        case .inspector:
            let desiredCanvas = min(
                max(
                    tuning.inspectorPriorityCanvasFraction * height,
                    tuning.inspectorPriorityCanvasRange.lowerBound
                ),
                tuning.inspectorPriorityCanvasRange.upperBound
            )
            let canvas = min(height, desiredCanvas)
            return ProfileV3PriorityWorkspaceSplit(
                mode: .stacked,
                priority: .inspector,
                canvas: canvas,
                inspector: max(0, height - canvas)
            )
        }
    }
}

// MARK: - Canvas long-press (#95 §F2 context operations, §F5.2 timing)

public enum ProfileV3LongPress {
    public static let minimumDuration = 0.45
    public static let maximumMovement = 10.0

    public static func isLongPress(elapsed: Double, movement: Double) -> Bool {
        elapsed >= minimumDuration && movement <= maximumMovement
    }

    /// Paste placement: the copied size anchored at the tapped atom.
    public static func pasteRect(copied: ProfileV3Rect, atX x: Int, y: Int) -> ProfileV3Rect {
        ProfileV3Rect(x: x, y: y, width: copied.width, height: copied.height)
    }
}
