import Testing
@testable import GestureIMEProfileAuthoring

@Test
func designReferenceWidthsMatchP13Contract() {
    #expect(
        ProfileV3DesignLayoutPolicy.contentInset(
            usableWidth: 320
        ) == 12
    )
    #expect(
        ProfileV3DesignLayoutPolicy.contentWidth(
            usableWidth: 320
        ) == 296
    )

    #expect(
        ProfileV3DesignLayoutPolicy.contentInset(
            usableWidth: 375
        ) == 16
    )
    #expect(
        ProfileV3DesignLayoutPolicy.contentWidth(
            usableWidth: 375
        ) == 343
    )

    #expect(
        ProfileV3DesignLayoutPolicy.contentInset(
            usableWidth: 390
        ) == 16
    )
    #expect(
        ProfileV3DesignLayoutPolicy.contentWidth(
            usableWidth: 390
        ) == 358
    )

    #expect(
        ProfileV3DesignLayoutPolicy.contentInset(
            usableWidth: 430
        ) == 16
    )
    #expect(
        ProfileV3DesignLayoutPolicy.contentWidth(
            usableWidth: 430
        ) == 398
    )

    #expect(
        ProfileV3DesignLayoutPolicy.contentInset(
            usableWidth: 600
        ) == 20
    )
}

@Test
func designRowsMatchP13MinimumGeometry() {
    #expect(
        ProfileV3DesignLayoutPolicy
            .continuousRowBaseHeight == 72
    )
    #expect(
        ProfileV3DesignLayoutPolicy
            .continuousLabelLineHeight == 28
    )
    #expect(
        ProfileV3DesignLayoutPolicy
            .continuousSliderAllocation == 44
    )
    #expect(
        ProfileV3DesignLayoutPolicy
            .colorRowMinimumHeight == 44
    )
}

@Test
func designPreviewHeightFollowsRuntimeScale() {
    #expect(
        ProfileV3DesignLayoutPolicy.previewHeight(
            baseKeyboardHeight: 344,
            keyboardHeightScale: 1
        ) == 344
    )
    #expect(
        ProfileV3DesignLayoutPolicy.previewHeight(
            baseKeyboardHeight: 216,
            keyboardHeightScale: 1.25
        ) == 270
    )
}
