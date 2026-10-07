import Testing
@testable import GestureIMEProfileAuthoring

@Test
func designReferenceWidthsMatchP13Insets() {
    #expect(ProfileV3DesignLayout.contentInset(width: 320) == 12)
    #expect(ProfileV3DesignLayout.contentWidth(width: 320) == 296)

    #expect(ProfileV3DesignLayout.contentInset(width: 375) == 16)
    #expect(ProfileV3DesignLayout.contentWidth(width: 375) == 343)

    #expect(ProfileV3DesignLayout.contentInset(width: 390) == 16)
    #expect(ProfileV3DesignLayout.contentWidth(width: 390) == 358)

    #expect(ProfileV3DesignLayout.contentInset(width: 430) == 16)
    #expect(ProfileV3DesignLayout.contentWidth(width: 430) == 398)

    #expect(ProfileV3DesignLayout.contentInset(width: 600) == 20)
    #expect(ProfileV3DesignLayout.contentWidth(width: 600) == 560)
}

@Test
func designSliderGrammarMatchesP13BaseGeometry() {
    #expect(ProfileV3DesignLayout.sliderRowBaseHeight == 72)
    #expect(ProfileV3DesignLayout.sliderLabelLineHeight == 28)
    #expect(ProfileV3DesignLayout.sliderControlLineHeight == 44)
    #expect(
        ProfileV3DesignLayout.sliderLabelLineHeight
            + ProfileV3DesignLayout.sliderControlLineHeight
            == ProfileV3DesignLayout.sliderRowBaseHeight
    )
    #expect(ProfileV3DesignLayout.minimumTouchExtent == 44)
}
