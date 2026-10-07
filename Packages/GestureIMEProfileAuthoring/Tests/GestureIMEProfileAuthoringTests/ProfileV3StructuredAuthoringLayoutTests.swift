import Testing
@testable import GestureIMEProfileAuthoring

@Test
func structuredAuthoringGeometryMatchesP13Contract() {
    #expect(ProfileV3StructuredAuthoringLayout.depthStep == 16)
    #expect(ProfileV3StructuredAuthoringLayout.railWidth == 1)
    #expect(ProfileV3StructuredAuthoringLayout.connectorLength == 8)
    #expect(ProfileV3StructuredAuthoringLayout.minimumTouchExtent == 44)
    #expect(ProfileV3StructuredAuthoringLayout.sliderRowHeight == 72)
    #expect(ProfileV3StructuredAuthoringLayout.sliderLabelLineHeight == 28)
    #expect(ProfileV3StructuredAuthoringLayout.sliderControlHeight == 44)

    #expect(ProfileV3StructuredAuthoringLayout.contentInset(width: 320) == 12)
    #expect(ProfileV3StructuredAuthoringLayout.contentWidth(width: 320) == 296)
    #expect(ProfileV3StructuredAuthoringLayout.contentInset(width: 375) == 16)
    #expect(ProfileV3StructuredAuthoringLayout.contentWidth(width: 375) == 343)
    #expect(ProfileV3StructuredAuthoringLayout.contentInset(width: 390) == 16)
    #expect(ProfileV3StructuredAuthoringLayout.contentWidth(width: 390) == 358)
    #expect(ProfileV3StructuredAuthoringLayout.contentInset(width: 430) == 16)
    #expect(ProfileV3StructuredAuthoringLayout.contentWidth(width: 430) == 398)
    #expect(ProfileV3StructuredAuthoringLayout.contentInset(width: 600) == 20)
    #expect(ProfileV3StructuredAuthoringLayout.indentation(depth: -1) == 0)
    #expect(ProfileV3StructuredAuthoringLayout.indentation(depth: 0) == 0)
    #expect(ProfileV3StructuredAuthoringLayout.indentation(depth: 3) == 48)
}
