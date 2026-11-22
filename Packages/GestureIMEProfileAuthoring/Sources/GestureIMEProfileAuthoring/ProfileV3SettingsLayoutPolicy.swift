import Foundation

/// #157 P13 / U8 deterministic Settings presentation policy.
///
/// Presentation only. ProductSettings storage/runtime semantics remain owned by
/// GestureIMEProductSettings.
public enum ProfileV3SettingsLayoutPolicy {
    public static let sliderRowBaseHeight = 72.0
    public static let sliderLabelLineHeight = 28.0
    public static let sliderAllocation = 44.0
    public static let ordinaryRowMinimumHeight = 44.0
    public static let sectionGap = 16.0

    /// Ordinary product UI range. Storage remains positive/unbounded for
    /// backwards compatibility and Developer diagnostics.
    public static let ordinaryHeightScaleRange = 0.80...1.25
    public static let ordinaryHeightScaleStep = 0.05

    public static func ordinaryHeightScaleValue(
        storedScale: Double
    ) -> Double {
        guard storedScale.isFinite else { return 1.0 }
        return min(
            ordinaryHeightScaleRange.upperBound,
            max(
                ordinaryHeightScaleRange.lowerBound,
                storedScale
            )
        )
    }

    public static func isOutsideOrdinaryHeightScaleRange(
        _ scale: Double
    ) -> Bool {
        !scale.isFinite
            || !ordinaryHeightScaleRange.contains(scale)
    }

    public static func contentInset(
        usableWidth: Double
    ) -> Double {
        if usableWidth <= 359 {
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

    /// Legacy raw-value mapping retained for diagnostics/backwards
    /// compatibility. The rebuilt ordinary Settings UI uses
    /// ordinaryHeightScaleRange instead.
    ///
    /// scale = 1 -> position = 0.5
    /// reciprocal scales are symmetric around the midpoint.
    public static func heightSliderPosition(
        scale: Double
    ) -> Double {
        guard scale.isFinite, scale > 0 else {
            return 0.5
        }

        return min(
            1,
            max(
                0,
                atan(scale) * 2 / Double.pi
            )
        )
    }

    /// Inverse of heightSliderPosition for ordinary finite Slider positions.
    /// Endpoints are nudged into the open interval so the produced semantic
    /// value always remains finite and positive.
    public static func heightScale(
        sliderPosition: Double
    ) -> Double {
        let epsilon = 1e-9
        let position = min(
            1 - epsilon,
            max(epsilon, sliderPosition)
        )
        return tan(position * Double.pi / 2)
    }
}
