import Foundation

/// #119 / frozen #95: the shared product-preview composition used by every
/// Main App preview entry point. Presentation code may scale this composition,
/// but ordinary preview routes do not selectively omit product primitives.
public enum ProfileV3PreviewPrimitive: String, CaseIterable, Hashable, Sendable {
    case candidateBar
    case boardKeys
    case flickGuides
    case relativeOverlay
}

public struct ProfileV3PreviewComposition: Equatable, Sendable {
    public let primitives: Set<ProfileV3PreviewPrimitive>

    public init(primitives: Set<ProfileV3PreviewPrimitive>) {
        self.primitives = primitives
    }

    public static let product = ProfileV3PreviewComposition(
        primitives: Set(ProfileV3PreviewPrimitive.allCases)
    )

    public func contains(_ primitive: ProfileV3PreviewPrimitive) -> Bool {
        primitives.contains(primitive)
    }
}
