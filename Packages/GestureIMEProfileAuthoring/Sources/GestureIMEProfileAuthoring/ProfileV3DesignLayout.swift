import Foundation

/// #157 P13 / U7 deterministic Design-screen geometry.
///
/// Values are base/minimum presentation geometry. Dynamic Type may increase
/// vertical allocations; callers must not clip content to these values.
public enum ProfileV3DesignLayout {
    public static let sliderRowBaseHeight = 72.0
    public static let sliderLabelLineHeight = 28.0
    public static let sliderControlLineHeight = 44.0
    public static let minimumTouchExtent = 44.0

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
        max(0, width - 2 * contentInset(width: width))
    }
}
