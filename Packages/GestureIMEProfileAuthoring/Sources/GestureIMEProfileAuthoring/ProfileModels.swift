import Foundation

public enum ProfileDirection: String, CaseIterable, Identifiable, Sendable {
    case n, ne, e, se, s, sw, w, nw
    public var id: String { rawValue }

    public var displayName: String {
        rawValue.uppercased()
    }
}

public struct ProfileValidation: Equatable, Sendable {
    public let valid: Bool
    public let errorCode: String?
    public let detail: String?

    public init(valid: Bool, errorCode: String? = nil, detail: String? = nil) {
        self.valid = valid
        self.errorCode = errorCode
        self.detail = detail
    }

    public static let validResult = ProfileValidation(valid: true)
}

public typealias ProfileValidator = @Sendable (Data) -> ProfileValidation

public struct ProfileSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let version: Int

    public init(id: String, name: String, version: Int) {
        self.id = id
        self.name = name
        self.version = version
    }
}

public struct ProfileGesturePolicy: Equatable, Sendable {
    public var deadZone: Double
    public var stage1CommitDistance: Double
    public var stage2CommitDistance: Double
    public var angularHysteresisDegrees: Double
    public var maxDirectionalStages: Int

    public init(
        deadZone: Double,
        stage1CommitDistance: Double,
        stage2CommitDistance: Double,
        angularHysteresisDegrees: Double,
        maxDirectionalStages: Int
    ) {
        self.deadZone = deadZone
        self.stage1CommitDistance = stage1CommitDistance
        self.stage2CommitDistance = stage2CommitDistance
        self.angularHysteresisDegrees = angularHysteresisDegrees
        self.maxDirectionalStages = maxDirectionalStages
    }
}

public struct ProfileKeySummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let role: String?
    public let row: Int
    public let column: Int
    public let width: Double
    public let height: Double

    public init(
        id: String,
        title: String,
        role: String?,
        row: Int,
        column: Int,
        width: Double,
        height: Double
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.row = row
        self.column = column
        self.width = width
        self.height = height
    }
}

public struct ProfileActionDraft: Equatable, Sendable {
    public var actionID: String
    public var arguments: [String: JSONNode]

    public init(actionID: String, arguments: [String: JSONNode] = [:]) {
        self.actionID = actionID
        self.arguments = arguments
    }
}

public struct ProfileBindingSummary: Identifiable, Equatable, Sendable {
    public let keyID: String
    public let path: [ProfileDirection]
    public let presentationText: String?
    public let actions: [ProfileActionDraft]

    public var id: String {
        keyID + ":" + (path.isEmpty ? "tap" : path.map(\.rawValue).joined(separator: ","))
    }

    public init(
        keyID: String,
        path: [ProfileDirection],
        presentationText: String?,
        actions: [ProfileActionDraft]
    ) {
        self.keyID = keyID
        self.path = path
        self.presentationText = presentationText
        self.actions = actions
    }
}
