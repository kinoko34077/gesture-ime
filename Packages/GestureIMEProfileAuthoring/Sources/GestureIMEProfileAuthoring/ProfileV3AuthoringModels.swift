import Foundation

public struct ProfileV3Rect: Hashable, Identifiable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var id: String { "\(x),\(y),\(width),\(height)" }
    public var maxX: Int { x + width }
    public var maxY: Int { y + height }

    public func overlapsPositiveArea(_ other: ProfileV3Rect) -> Bool {
        x < other.maxX
            && other.x < maxX
            && y < other.maxY
            && other.y < maxY
    }
}

public enum ProfileV3TransitionLifetime: String, CaseIterable, Identifiable, Sendable {
    case persistent
    case transient

    public var id: String { rawValue }
}

public struct ProfileV3TransitionDraft: Equatable, Sendable {
    public var targetBoardID: String
    public var lifetime: ProfileV3TransitionLifetime

    public init(
        targetBoardID: String,
        lifetime: ProfileV3TransitionLifetime = .transient
    ) {
        self.targetBoardID = targetBoardID
        self.lifetime = lifetime
    }
}

public struct ProfileV3RepeatDraft: Equatable, Sendable {
    public var intervalMs: Int
    public var actions: [ProfileActionDraft]

    public init(intervalMs: Int, actions: [ProfileActionDraft]) {
        self.intervalMs = intervalMs
        self.actions = actions
    }
}

public struct ProfileV3HoldDraft: Equatable, Sendable {
    public var delayMs: Int
    public var onStart: [ProfileActionDraft]
    public var transition: ProfileV3TransitionDraft?
    public var repeatBehavior: ProfileV3RepeatDraft?
    public var suppressOnReleaseAfterStart: Bool

    public init(
        delayMs: Int,
        onStart: [ProfileActionDraft] = [],
        transition: ProfileV3TransitionDraft? = nil,
        repeatBehavior: ProfileV3RepeatDraft? = nil,
        suppressOnReleaseAfterStart: Bool = false
    ) {
        self.delayMs = delayMs
        self.onStart = onStart
        self.transition = transition
        self.repeatBehavior = repeatBehavior
        self.suppressOnReleaseAfterStart = suppressOnReleaseAfterStart
    }
}

public struct ProfileV3LayerSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let rootBoardID: String
    public let isInitial: Bool

    public init(id: String, name: String?, rootBoardID: String, isInitial: Bool) {
        self.id = id
        self.name = name
        self.rootBoardID = rootBoardID
        self.isInitial = isInitial
    }
}

public struct ProfileV3HoldSummary: Equatable, Sendable {
    public let delayMs: Int
    public let onStart: [ProfileActionDraft]
    public let transition: ProfileV3TransitionDraft?
    public let repeatIntervalMs: Int?
    public let repeatActions: [ProfileActionDraft]
    public let suppressOnReleaseAfterStart: Bool

    public init(
        delayMs: Int,
        onStart: [ProfileActionDraft],
        transition: ProfileV3TransitionDraft?,
        repeatIntervalMs: Int?,
        repeatActions: [ProfileActionDraft],
        suppressOnReleaseAfterStart: Bool
    ) {
        self.delayMs = delayMs
        self.onStart = onStart
        self.transition = transition
        self.repeatIntervalMs = repeatIntervalMs
        self.repeatActions = repeatActions
        self.suppressOnReleaseAfterStart = suppressOnReleaseAfterStart
    }
}

public struct ProfileV3BoardEntrySummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let rect: ProfileV3Rect
    public let presentationText: String?
    public let accessibilityLabel: String?
    public let caseCount: Int
    public let onRelease: [ProfileActionDraft]
    public let transition: ProfileV3TransitionDraft?
    public let hold: ProfileV3HoldSummary?

    public init(
        id: String,
        rect: ProfileV3Rect,
        presentationText: String?,
        accessibilityLabel: String?,
        caseCount: Int,
        onRelease: [ProfileActionDraft],
        transition: ProfileV3TransitionDraft?,
        hold: ProfileV3HoldSummary?
    ) {
        self.id = id
        self.rect = rect
        self.presentationText = presentationText
        self.accessibilityLabel = accessibilityLabel
        self.caseCount = caseCount
        self.onRelease = onRelease
        self.transition = transition
        self.hold = hold
    }
}

public struct ProfileV3BoardSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let entryCount: Int
    public let inboundReferenceCount: Int

    public init(id: String, entryCount: Int, inboundReferenceCount: Int) {
        self.id = id
        self.entryCount = entryCount
        self.inboundReferenceCount = inboundReferenceCount
    }
}

public enum ProfileV3BoardReferenceKind: String, Sendable {
    case layerRoot
    case entryTransition
    case holdTransition
}

public struct ProfileV3BoardReference: Identifiable, Equatable, Sendable {
    public let kind: ProfileV3BoardReferenceKind
    public let targetBoardID: String
    public let layerID: String?
    public let sourceBoardID: String?
    public let sourceEntryID: String?
    public let path: String

    public init(
        kind: ProfileV3BoardReferenceKind,
        targetBoardID: String,
        layerID: String? = nil,
        sourceBoardID: String? = nil,
        sourceEntryID: String? = nil,
        path: String
    ) {
        self.kind = kind
        self.targetBoardID = targetBoardID
        self.layerID = layerID
        self.sourceBoardID = sourceBoardID
        self.sourceEntryID = sourceEntryID
        self.path = path
    }

    public var id: String {
        [
            kind.rawValue,
            targetBoardID,
            layerID ?? "",
            sourceBoardID ?? "",
            sourceEntryID ?? "",
            path
        ].joined(separator: ":")
    }
}

public enum ProfileV3StateType: String, CaseIterable, Identifiable, Sendable {
    case boolean
    case enumeration = "enum"

    public var id: String { rawValue }
}

public struct ProfileV3StateSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let type: ProfileV3StateType
    public let values: [String]
    public let defaultValue: JSONNode

    public init(
        id: String,
        type: ProfileV3StateType,
        values: [String],
        defaultValue: JSONNode
    ) {
        self.id = id
        self.type = type
        self.values = values
        self.defaultValue = defaultValue
    }
}

public struct ProfileV3TransformEntry: Identifiable, Equatable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    public var id: String { from }
}

public struct ProfileV3TransformTableSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let entries: [ProfileV3TransformEntry]

    public init(id: String, entries: [ProfileV3TransformEntry]) {
        self.id = id
        self.entries = entries
    }
}

public struct ProfileV3MacroSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let actions: [ProfileActionDraft]
    /// False when the raw Macro contains Action nodes that cannot be represented
    /// losslessly by ordinary structured authoring.
    public let actionsEditable: Bool

    public init(
        id: String,
        actions: [ProfileActionDraft],
        actionsEditable: Bool = true
    ) {
        self.id = id
        self.actions = actions
        self.actionsEditable = actionsEditable
    }
}


public struct ProfileV3ResolverCaseDraft: Equatable, Sendable {
    public var condition: JSONNode
    public var behavior: ProfileV3EndpointDraft

    public init(condition: JSONNode, behavior: ProfileV3EndpointDraft) {
        self.condition = condition
        self.behavior = behavior
    }
}

public struct ProfileV3EndpointDraft: Equatable, Sendable {
    public var presentationText: String?
    public var accessibilityLabel: String?
    public var actions: [ProfileActionDraft]
    public var transition: ProfileV3TransitionDraft?
    public var hold: ProfileV3HoldDraft?

    public init(
        presentationText: String? = nil,
        accessibilityLabel: String? = nil,
        actions: [ProfileActionDraft] = [],
        transition: ProfileV3TransitionDraft? = nil,
        hold: ProfileV3HoldDraft? = nil
    ) {
        self.presentationText = presentationText
        self.accessibilityLabel = accessibilityLabel
        self.actions = actions
        self.transition = transition
        self.hold = hold
    }
}

public enum ProfileV3PlacementIssue: Equatable, Sendable {
    case invalidRect
    case outOfBounds
    case extentExceeded
    case overlap(entryID: String)
}


public enum ProfileV3SemanticSection: String, CaseIterable, Identifiable, Sendable {
    case states
    case transformTables
    case macros

    public var id: String { rawValue }
}
