import Foundation

/// #157 P13 / U3 shared structured-authoring geometry.
///
/// This type contains presentation constants only. It deliberately owns no
/// Profile, JSON, mutation or persistence behavior.
public enum ProfileV3StructuredAuthoringLayout {
    public static let depthStep = 16.0
    public static let railWidth = 1.0
    public static let connectorLength = 8.0
    public static let minimumTouchExtent = 44.0

    /// #157 P13 shared phone form geometry used by Design and Settings.
    public static let sliderRowHeight = 72.0
    public static let sliderLabelLineHeight = 28.0
    public static let sliderControlHeight = 44.0

    public static func contentInset(width: Double) -> Double {
        if width <= 359 {
            return 12
        }
        if width < 600 {
            return 16
        }
        return 20
    }

    public static func contentWidth(width: Double) -> Double {
        width - 2 * contentInset(width: width)
    }

    public static func indentation(depth: Int) -> Double {
        Double(max(0, depth)) * depthStep
    }
}
