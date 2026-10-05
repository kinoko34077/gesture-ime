import Testing
@testable import GestureIMEProfileAuthoring

@Test
func productPreviewCompositionContainsEveryRequiredPrimitive() {
    let product = ProfileV3PreviewComposition.product

    #expect(product.primitives == Set(ProfileV3PreviewPrimitive.allCases))
    #expect(product.contains(.candidateBar))
    #expect(product.contains(.boardKeys))
    #expect(product.contains(.flickGuides))
    #expect(product.contains(.relativeOverlay))
}
