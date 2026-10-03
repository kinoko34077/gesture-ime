import Foundation

public struct ProfileBoardCoordinate: Hashable, Identifiable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public var id: String { "\(x),\(y)" }
    public var displayName: String { "(\(x), \(y))" }
}

public enum ProfileBoardTransitionLifetime: String, CaseIterable, Identifiable, Sendable {
    case persistent
    case transient

    public var id: String { rawValue }
}

public struct ProfileBoardTransitionDraft: Equatable, Sendable {
    public var targetBoardID: String
    public var lifetime: ProfileBoardTransitionLifetime

    public init(
        targetBoardID: String,
        lifetime: ProfileBoardTransitionLifetime = .transient
    ) {
        self.targetBoardID = targetBoardID
        self.lifetime = lifetime
    }
}

public struct ProfileBoardEntrySummary: Identifiable, Equatable, Sendable {
    public var coordinate: ProfileBoardCoordinate
    public var presentationText: String?
    public var actions: [ProfileActionDraft]
    public var transition: ProfileBoardTransitionDraft?

    public var id: String { coordinate.id }

    public init(
        coordinate: ProfileBoardCoordinate,
        presentationText: String?,
        actions: [ProfileActionDraft],
        transition: ProfileBoardTransitionDraft?
    ) {
        self.coordinate = coordinate
        self.presentationText = presentationText
        self.actions = actions
        self.transition = transition
    }
}

public struct ProfileBoardTriggerSummary: Equatable, Sendable {
    public var delayMs: Int
    public var transition: ProfileBoardTransitionDraft

    public init(delayMs: Int, transition: ProfileBoardTransitionDraft) {
        self.delayMs = delayMs
        self.transition = transition
    }
}

public struct ProfileBoardSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let entryCount: Int
    public let holdTrigger: ProfileBoardTriggerSummary?

    public init(id: String, entryCount: Int, holdTrigger: ProfileBoardTriggerSummary?) {
        self.id = id
        self.entryCount = entryCount
        self.holdTrigger = holdTrigger
    }
}

public struct ProfileBoardEntryPointSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let layerID: String
    public let keyID: String
    public let boardID: String

    public init(id: String, layerID: String, keyID: String, boardID: String) {
        self.id = id
        self.layerID = layerID
        self.keyID = keyID
        self.boardID = boardID
    }
}
