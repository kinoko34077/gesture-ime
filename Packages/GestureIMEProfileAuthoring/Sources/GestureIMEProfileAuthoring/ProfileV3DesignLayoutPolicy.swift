import Foundation

/// #157 P13 / U7 deterministic Design-tab geometry.
///
/// Presentation constants only. Theme/Profile/runtime semantics are not owned
/// here.
public enum ProfileV3DesignLayoutPolicy {
    public static let continuousRowBaseHeight = 72.0
    public static let continuousLabelLineHeight = 28.0
    public static let continuousSliderAllocation = 44.0
    public static let colorRowMinimumHeight = 44.0
    public static let sectionGap = 16.0
    public static let sectionHeadingBaseHeight = 28.0

    public static func contentInset(
        usableWidth: Double
    ) -> Double {
        if usableWidth < 360 {
            return 12
        }
        if usableWidth < 600 {
            return 16
        }
        return 20
    }

    public static func contentWidth(
        usableWidth: Double
    ) -> Double {
        max(
            0,
            usableWidth
                - 2 * contentInset(
                    usableWidth: usableWidth
                )
        )
    }

}
