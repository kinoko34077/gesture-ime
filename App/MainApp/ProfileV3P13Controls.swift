import SwiftUI
import GestureIMEProfileAuthoring

/// #157 P13 two-line compact Slider grammar shared by Design and Settings.
struct ProfileV3P13SliderRow: View {
    let title: String
    let displayValue: String
    let range: ClosedRange<Double>
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)

                Spacer(minLength: 8)

                Text(displayValue)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(
                minHeight: CGFloat(
                    ProfileV3DesignLayout.sliderLabelLineHeight
                )
            )

            Slider(
                value: $value,
                in: range
            )
            .frame(
                minHeight: CGFloat(
                    ProfileV3DesignLayout.sliderControlLineHeight
                )
            )
            .accessibilityLabel(title)
            .accessibilityValue(displayValue)
        }
        .frame(
            minHeight: CGFloat(
                ProfileV3DesignLayout.sliderRowBaseHeight
            )
        )
    }
}
