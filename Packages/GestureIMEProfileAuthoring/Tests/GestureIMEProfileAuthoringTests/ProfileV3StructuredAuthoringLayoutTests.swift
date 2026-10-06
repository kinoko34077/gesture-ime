import Testing
@testable import GestureIMEProfileAuthoring

@Test
func structuredAuthoringGeometryMatchesP13Contract() {
    #expect(ProfileV3StructuredAuthoringLayout.depthStep == 16)
    #expect(ProfileV3StructuredAuthoringLayout.railWidth == 1)
    #expect(ProfileV3StructuredAuthoringLayout.connectorLength == 8)
    #expect(ProfileV3StructuredAuthoringLayout.minimumTouchExtent == 44)
    #expect(ProfileV3StructuredAuthoringLayout.indentation(depth: -1) == 0)
    #expect(ProfileV3StructuredAuthoringLayout.indentation(depth: 0) == 0)
    #expect(ProfileV3StructuredAuthoringLayout.indentation(depth: 3) == 48)
}
