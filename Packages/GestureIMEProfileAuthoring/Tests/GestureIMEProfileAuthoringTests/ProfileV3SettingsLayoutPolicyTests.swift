import Testing
@testable import GestureIMEProfileAuthoring

@Test
func settingsReferenceWidthsMatchP13Contract() {
    #expect(
        ProfileV3SettingsLayoutPolicy.contentInset(
            usableWidth: 320
        ) == 12
    )
    #expect(
        ProfileV3SettingsLayoutPolicy.contentWidth(
            usableWidth: 320
        ) == 296
    )

    #expect(
        ProfileV3SettingsLayoutPolicy.contentInset(
            usableWidth: 375
        ) == 16
    )
    #expect(
        ProfileV3SettingsLayoutPolicy.contentWidth(
            usableWidth: 375
        ) == 343
    )

    #expect(
        ProfileV3SettingsLayoutPolicy.contentInset(
            usableWidth: 390
        ) == 16
    )
    #expect(
        ProfileV3SettingsLayoutPolicy.contentWidth(
            usableWidth: 390
        ) == 358
    )

    #expect(
        ProfileV3SettingsLayoutPolicy.contentInset(
            usableWidth: 430
        ) == 16
    )
    #expect(
        ProfileV3SettingsLayoutPolicy.contentWidth(
            usableWidth: 430
        ) == 398
    )
}

@Test
func settingsRowsMatchP13MinimumGeometry() {
    #expect(
        ProfileV3SettingsLayoutPolicy
            .sliderRowBaseHeight == 72
    )
    #expect(
        ProfileV3SettingsLayoutPolicy
            .sliderLabelLineHeight == 28
    )
    #expect(
        ProfileV3SettingsLayoutPolicy
            .sliderAllocation == 44
    )
    #expect(
        ProfileV3SettingsLayoutPolicy
            .ordinaryRowMinimumHeight == 44
    )
}

@Test
func positiveHeightScaleUsesUnboundedSemanticSliderMapping() {
    #expect(
        abs(
            ProfileV3SettingsLayoutPolicy
                .heightSliderPosition(scale: 1)
                - 0.5
        ) < 1e-12
    )

    for scale in [0.1, 0.5, 1, 2, 10, 100] {
        let position =
            ProfileV3SettingsLayoutPolicy
                .heightSliderPosition(scale: scale)
        let roundTrip =
            ProfileV3SettingsLayoutPolicy
                .heightScale(
                    sliderPosition: position
                )

        #expect(position > 0)
        #expect(position < 1)
        #expect(
            abs(roundTrip - scale)
                / scale
                < 1e-10
        )
    }

    #expect(
        ProfileV3SettingsLayoutPolicy
            .heightSliderPosition(scale: 0.5)
            <
        ProfileV3SettingsLayoutPolicy
            .heightSliderPosition(scale: 1)
    )
    #expect(
        ProfileV3SettingsLayoutPolicy
            .heightSliderPosition(scale: 1)
            <
        ProfileV3SettingsLayoutPolicy
            .heightSliderPosition(scale: 2)
    )
}


@Test
func ordinaryKeyboardHeightRangeIsBoundedAndClampsPresentationOnly() {
    #expect(
        ProfileV3SettingsLayoutPolicy
            .ordinaryHeightScaleRange == 0.80...1.25
    )
    #expect(
        ProfileV3SettingsLayoutPolicy
            .ordinaryHeightScaleStep == 0.05
    )
    #expect(
        ProfileV3SettingsLayoutPolicy
            .ordinaryHeightScaleValue(storedScale: 0.1) == 0.80
    )
    #expect(
        ProfileV3SettingsLayoutPolicy
            .ordinaryHeightScaleValue(storedScale: 1.0) == 1.0
    )
    #expect(
        ProfileV3SettingsLayoutPolicy
            .ordinaryHeightScaleValue(storedScale: 8.0) == 1.25
    )
    #expect(
        ProfileV3SettingsLayoutPolicy
            .isOutsideOrdinaryHeightScaleRange(0.79)
    )
    #expect(
        !ProfileV3SettingsLayoutPolicy
            .isOutsideOrdinaryHeightScaleRange(1.0)
    )
}
