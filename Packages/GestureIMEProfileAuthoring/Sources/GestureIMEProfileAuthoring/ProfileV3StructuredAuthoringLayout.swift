import Foundation

/// #157 P13 / U3 shared structured-authoring geometry.
///
/// This type contains presentation constants only. It deliberately owns no
/// Profile, JSON, mutation or persistence behavior.
public enum ProfileV3StructuredAuthoringLayout {
    public static let depthStep = 16.0
    public static let railWidth = 1.0
    public static let connectorLength = 8.0
    public static let minimumTouchExtent = 44.0

    public static func indentation(depth: Int) -> Double {
        Double(max(0, depth)) * depthStep
    }
}
