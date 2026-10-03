import Foundation

extension ProfileDocument {
    public func boardSummaries() throws -> [ProfileBoardSummary] {
        guard isBoardGraphV2 else { return [] }
        return try boardArray().compactMap { node in
            guard
                let object = node.objectValue,
                let id = object["id"]?.stringValue
            else { return nil }

            let entries = object["entries"]?.arrayValue ?? []
            let hold = Self.boardHoldTrigger(from: object)
            return ProfileBoardSummary(
                id: id,
                entryCount: entries.count,
                holdTrigger: hold
            )
        }
        .sorted { $0.id < $1.id }
    }

    public func boardIDs() throws -> [String] {
        try boardSummaries().map(\.id)
    }

    public func entryPoint(
        layerID: String,
        keyID: String
    ) throws -> ProfileBoardEntryPointSummary? {
        guard isBoardGraphV2 else { return nil }
        return try entryPointArray().compactMap { node -> ProfileBoardEntryPointSummary? in
            guard
                let object = node.objectValue,
                object["layerID"]?.stringValue == layerID,
                object["keyID"]?.stringValue == keyID,
                object["trigger"]?.stringValue == "press",
                let id = object["id"]?.stringValue,
                let boardID = object["boardRef"]?.stringValue
            else { return nil }
            return ProfileBoardEntryPointSummary(
                id: id,
                layerID: layerID,
                keyID: keyID,
                boardID: boardID
            )
        }.first
    }

    public func boardEntries(boardID: String) throws -> [ProfileBoardEntrySummary] {
        guard isBoardGraphV2 else { return [] }
        let board = try boardObject(id: boardID)
        return (board["entries"]?.arrayValue ?? []).compactMap(Self.boardEntrySummary)
            .sorted {
                if $0.coordinate.y != $1.coordinate.y {
                    return $0.coordinate.y < $1.coordinate.y
                }
                return $0.coordinate.x < $1.coordinate.x
            }
    }

    public func boardHoldTrigger(boardID: String) throws -> ProfileBoardTriggerSummary? {
        guard isBoardGraphV2 else { return nil }
        return Self.boardHoldTrigger(from: try boardObject(id: boardID))
    }

    public mutating func createBoard(id: String) throws {
        guard isBoardGraphV2 else {
            throw ProfileAuthoringError.invalidJSON("Board editing requires Profile v2")
        }
        let cleanID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else {
            throw ProfileAuthoringError.missingField("board.id")
        }

        var rootObject = try boardTopObject()
        var boards = rootObject["boards"]?.arrayValue ?? []
        if boards.contains(where: { $0.objectValue?["id"]?.stringValue == cleanID }) {
            throw ProfileAuthoringError.duplicateProfile(cleanID)
        }
        boards.append(.object([
            "id": .string(cleanID),
            "selectionPolicy": .object(["kind": .string("relativeCoordinate")]),
            "entries": .array([])
        ]))
        rootObject["boards"] = .array(boards)
        root = .object(rootObject)
    }

    public mutating func setEntryPointBoard(
        layerID: String,
        keyID: String,
        boardID: String
    ) throws {
        guard isBoardGraphV2 else {
            throw ProfileAuthoringError.invalidJSON("Entry-point editing requires Profile v2")
        }
        _ = try boardObject(id: boardID)

        var rootObject = try boardTopObject()
        var entryPoints = rootObject["entryPoints"]?.arrayValue ?? []
        if let index = entryPoints.firstIndex(where: { node in
            guard let object = node.objectValue else { return false }
            return object["layerID"]?.stringValue == layerID
                && object["keyID"]?.stringValue == keyID
                && object["trigger"]?.stringValue == "press"
        }) {
            var object = entryPoints[index].objectValue ?? [:]
            object["boardRef"] = .string(boardID)
            entryPoints[index] = .object(object)
        } else {
            entryPoints.append(.object([
                "id": .string(Self.safeSemanticID("entry.\(layerID).\(keyID)")),
                "layerID": .string(layerID),
                "keyID": .string(keyID),
                "trigger": .string("press"),
                "boardRef": .string(boardID)
            ]))
        }
        rootObject["entryPoints"] = .array(entryPoints)
        root = .object(rootObject)
    }

    public mutating func upsertBoardEntry(
        boardID: String,
        originalCoordinate: ProfileBoardCoordinate?,
        coordinate: ProfileBoardCoordinate,
        presentationText: String?,
        actions: [ProfileActionDraft],
        transition: ProfileBoardTransitionDraft?
    ) throws {
        guard isBoardGraphV2 else {
            throw ProfileAuthoringError.invalidJSON("Board entry editing requires Profile v2")
        }
        guard (-32...32).contains(coordinate.x), (-32...32).contains(coordinate.y) else {
            throw ProfileAuthoringError.invalidJSON("Board coordinates must be within -32...32")
        }

        var rootObject = try boardTopObject()
        var boards = rootObject["boards"]?.arrayValue ?? []
        guard let boardIndex = boards.firstIndex(where: {
            $0.objectValue?["id"]?.stringValue == boardID
        }) else {
            throw ProfileAuthoringError.missingReference(boardID)
        }

        var board = boards[boardIndex].objectValue ?? [:]
        var entries = board["entries"]?.arrayValue ?? []

        if let originalCoordinate, originalCoordinate != coordinate {
            entries.removeAll {
                Self.coordinate(from: $0.objectValue?["coordinate"]) == originalCoordinate
            }
        }

        let index = entries.firstIndex {
            Self.coordinate(from: $0.objectValue?["coordinate"]) == coordinate
        }

        var entry = index.flatMap { entries[$0].objectValue } ?? [:]
        entry["coordinate"] = Self.coordinateNode(coordinate)

        if let presentationText, !presentationText.isEmpty {
            var presentation = entry["presentation"]?.objectValue ?? [:]
            presentation["text"] = .string(presentationText)
            entry["presentation"] = .object(presentation)
        } else {
            entry.removeValue(forKey: "presentation")
        }

        entry["onRelease"] = .array(actions.map(Self.boardActionNode))

        if let transition {
            entry["transition"] = Self.transitionNode(transition)
        } else {
            entry.removeValue(forKey: "transition")
        }

        if let index {
            entries[index] = .object(entry)
        } else {
            entries.append(.object(entry))
        }

        board["entries"] = .array(entries)
        boards[boardIndex] = .object(board)
        rootObject["boards"] = .array(boards)
        root = .object(rootObject)
    }

    public mutating func removeBoardEntry(
        boardID: String,
        coordinate: ProfileBoardCoordinate
    ) throws {
        guard isBoardGraphV2 else { return }
        var rootObject = try boardTopObject()
        var boards = rootObject["boards"]?.arrayValue ?? []
        guard let boardIndex = boards.firstIndex(where: {
            $0.objectValue?["id"]?.stringValue == boardID
        }) else {
            throw ProfileAuthoringError.missingReference(boardID)
        }
        var board = boards[boardIndex].objectValue ?? [:]
        var entries = board["entries"]?.arrayValue ?? []
        entries.removeAll {
            Self.coordinate(from: $0.objectValue?["coordinate"]) == coordinate
        }
        board["entries"] = .array(entries)
        boards[boardIndex] = .object(board)
        rootObject["boards"] = .array(boards)
        root = .object(rootObject)
    }

    public mutating func setBoardHoldTransition(
        boardID: String,
        delayMs: Int,
        transition: ProfileBoardTransitionDraft?
    ) throws {
        guard isBoardGraphV2 else {
            throw ProfileAuthoringError.invalidJSON("Board trigger editing requires Profile v2")
        }

        var rootObject = try boardTopObject()
        var boards = rootObject["boards"]?.arrayValue ?? []
        guard let boardIndex = boards.firstIndex(where: {
            $0.objectValue?["id"]?.stringValue == boardID
        }) else {
            throw ProfileAuthoringError.missingReference(boardID)
        }

        var board = boards[boardIndex].objectValue ?? [:]
        var triggers = board["triggers"]?.arrayValue ?? []
        triggers.removeAll {
            $0.objectValue?["type"]?.stringValue == "hold"
        }

        if let transition {
            triggers.append(.object([
                "type": .string("hold"),
                "delayMs": .integer(Int64(min(max(delayMs, 50), 5000))),
                "transition": Self.transitionNode(transition)
            ]))
        }

        if triggers.isEmpty {
            board.removeValue(forKey: "triggers")
        } else {
            board["triggers"] = .array(triggers)
        }
        boards[boardIndex] = .object(board)
        rootObject["boards"] = .array(boards)
        root = .object(rootObject)
    }

    private func boardTopObject() throws -> [String: JSONNode] {
        guard let object = root.objectValue else {
            throw ProfileAuthoringError.invalidJSON("Profile root must be an object")
        }
        return object
    }

    private func boardArray() throws -> [JSONNode] {
        guard let boards = try boardTopObject()["boards"]?.arrayValue else {
            throw ProfileAuthoringError.missingField("boards")
        }
        return boards
    }

    private func entryPointArray() throws -> [JSONNode] {
        guard let entryPoints = try boardTopObject()["entryPoints"]?.arrayValue else {
            throw ProfileAuthoringError.missingField("entryPoints")
        }
        return entryPoints
    }

    private func boardObject(id: String) throws -> [String: JSONNode] {
        guard let board = try boardArray()
            .first(where: { $0.objectValue?["id"]?.stringValue == id })?
            .objectValue else {
            throw ProfileAuthoringError.missingReference(id)
        }
        return board
    }

    private static func boardEntrySummary(_ node: JSONNode) -> ProfileBoardEntrySummary? {
        guard
            let object = node.objectValue,
            let coordinate = coordinate(from: object["coordinate"])
        else { return nil }

        let presentation = object["presentation"]?.objectValue?["text"]?.stringValue
        let actions = (object["onRelease"]?.arrayValue ?? []).compactMap(boardActionDraft)
        let transition = object["transition"].flatMap(boardTransitionDraft)

        return ProfileBoardEntrySummary(
            coordinate: coordinate,
            presentationText: presentation,
            actions: actions,
            transition: transition
        )
    }

    private static func boardHoldTrigger(from board: [String: JSONNode]) -> ProfileBoardTriggerSummary? {
        guard let trigger = (board["triggers"]?.arrayValue ?? [])
            .compactMap(\.objectValue)
            .first(where: { $0["type"]?.stringValue == "hold" }),
              let transitionNode = trigger["transition"],
              let transition = boardTransitionDraft(transitionNode)
        else { return nil }

        return ProfileBoardTriggerSummary(
            delayMs: trigger["delayMs"]?.intValue ?? 500,
            transition: transition
        )
    }

    private static func coordinate(from node: JSONNode?) -> ProfileBoardCoordinate? {
        guard
            let object = node?.objectValue,
            let x = object["x"]?.intValue,
            let y = object["y"]?.intValue
        else { return nil }
        return ProfileBoardCoordinate(x: x, y: y)
    }

    private static func coordinateNode(_ coordinate: ProfileBoardCoordinate) -> JSONNode {
        .object([
            "x": .integer(Int64(coordinate.x)),
            "y": .integer(Int64(coordinate.y))
        ])
    }

    private static func boardActionDraft(_ node: JSONNode) -> ProfileActionDraft? {
        guard
            let object = node.objectValue,
            let id = object["actionID"]?.stringValue,
            let arguments = object["arguments"]?.objectValue
        else { return nil }
        return ProfileActionDraft(actionID: id, arguments: arguments)
    }

    private static func boardActionNode(_ action: ProfileActionDraft) -> JSONNode {
        .object([
            "actionID": .string(action.actionID),
            "arguments": .object(action.arguments)
        ])
    }

    private static func boardTransitionDraft(_ node: JSONNode) -> ProfileBoardTransitionDraft? {
        guard
            let object = node.objectValue,
            let target = object["targetBoardRef"]?.stringValue,
            let lifetimeRaw = object["lifetime"]?.stringValue,
            let lifetime = ProfileBoardTransitionLifetime(rawValue: lifetimeRaw)
        else { return nil }
        return ProfileBoardTransitionDraft(
            targetBoardID: target,
            lifetime: lifetime
        )
    }

    private static func transitionNode(_ transition: ProfileBoardTransitionDraft) -> JSONNode {
        .object([
            "targetBoardRef": .string(transition.targetBoardID),
            "lifetime": .string(transition.lifetime.rawValue)
        ])
    }

    private static func safeSemanticID(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let mapped = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(String(scalar)) : "_"
        }
        return String(mapped.prefix(128))
    }
}
