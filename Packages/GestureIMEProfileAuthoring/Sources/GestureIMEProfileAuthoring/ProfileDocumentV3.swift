import Foundation

extension ProfileDocument {
    public static func emptyV3(
        id: String,
        name: String
    ) throws -> ProfileDocument {
        let cleanID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try v3ValidateSemanticID(cleanID, field: "id")
        guard !cleanName.isEmpty, cleanName.unicodeScalars.count <= 128 else {
            throw ProfileAuthoringError.invalidJSON("Profile name must contain 1...128 Unicode scalars")
        }

        // These are generic authoring-seed values, not frozen product tuning.
        let root = JSONNode.object([
            "schema": .string("gesture-ime.profile.v3"),
            "id": .string(cleanID),
            "name": .string(cleanName),
            "version": .integer(1),
            "gesturePolicy": .object([
                "deadZone": .decimal(0.15),
                "initialCellCommitDistance": .decimal(0.55),
                "subsequentCellCommitDistance": .decimal(0.45),
                "angularHysteresisDegrees": .decimal(8)
            ]),
            "initialLayerRef": .string("layer.base"),
            "layers": .array([
                .object([
                    "id": .string("layer.base"),
                    "name": .string("Base"),
                    "rootBoardRef": .string("board.base")
                ])
            ]),
            "boards": .array([
                .object([
                    "id": .string("board.base"),
                    "entries": .array([])
                ])
            ]),
            "states": .array([]),
            "transformTables": .array([]),
            "macros": .array([])
        ])
        let data = try JSONSerialization.data(
            withJSONObject: root.foundationValue,
            options: [.sortedKeys]
        )
        return try ProfileDocument(data: data)
    }

    public func v3InitialLayerID() throws -> String {
        let root = try v3TopObject()
        guard let value = root["initialLayerRef"]?.stringValue else {
            throw ProfileAuthoringError.missingField("initialLayerRef")
        }
        return value
    }

    public func v3LayerSummaries() throws -> [ProfileV3LayerSummary] {
        let initial = try v3InitialLayerID()
        return try v3Array(named: "layers").compactMap { node in
            guard
                let object = node.objectValue,
                let id = object["id"]?.stringValue,
                let rootBoard = object["rootBoardRef"]?.stringValue
            else {
                return nil
            }
            return ProfileV3LayerSummary(
                id: id,
                name: object["name"]?.stringValue,
                rootBoardID: rootBoard,
                isInitial: id == initial
            )
        }
    }

    public func v3BoardSummaries() throws -> [ProfileV3BoardSummary] {
        let refs = try v3AllBoardReferences()
        return try v3Array(named: "boards").compactMap { node in
            guard
                let object = node.objectValue,
                let id = object["id"]?.stringValue
            else {
                return nil
            }
            return ProfileV3BoardSummary(
                id: id,
                entryCount: object["entries"]?.arrayValue?.count ?? 0,
                inboundReferenceCount: refs.filter { $0.targetBoardID == id }.count
            )
        }
    }

    public func v3BoardEntries(boardID: String) throws -> [ProfileV3BoardEntrySummary] {
        let board = try v3ObjectInArray(named: "boards", id: boardID)
        return (board["entries"]?.arrayValue ?? []).compactMap(Self.v3EntrySummary)
            .sorted {
                if $0.rect.y != $1.rect.y { return $0.rect.y < $1.rect.y }
                if $0.rect.x != $1.rect.x { return $0.rect.x < $1.rect.x }
                return $0.id < $1.id
            }
    }

    public func v3EntryResolver(
        boardID: String,
        entryID: String
    ) throws -> JSONNode {
        let entry = try v3EntryObject(boardID: boardID, entryID: entryID)
        guard let resolver = entry["resolver"] else {
            throw ProfileAuthoringError.missingField("resolver")
        }
        return resolver
    }

    public func v3InboundReferences(to boardID: String) throws -> [ProfileV3BoardReference] {
        try v3AllBoardReferences().filter { $0.targetBoardID == boardID }
    }

    public func v3StateSummaries() throws -> [ProfileV3StateSummary] {
        try v3Array(named: "states").compactMap { node in
            guard
                let object = node.objectValue,
                let id = object["id"]?.stringValue,
                let rawType = object["type"]?.stringValue,
                let type = ProfileV3StateType(rawValue: rawType),
                let defaultValue = object["default"]
            else {
                return nil
            }
            return ProfileV3StateSummary(
                id: id,
                type: type,
                values: object["values"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                defaultValue: defaultValue
            )
        }
    }

    public func v3TransformTableSummaries() throws -> [ProfileV3TransformTableSummary] {
        try v3Array(named: "transformTables").compactMap { node in
            guard
                let object = node.objectValue,
                let id = object["id"]?.stringValue
            else {
                return nil
            }
            let entries = (object["entries"]?.arrayValue ?? []).compactMap { entry -> ProfileV3TransformEntry? in
                guard
                    let item = entry.objectValue,
                    let from = item["from"]?.stringValue,
                    let to = item["to"]?.stringValue
                else {
                    return nil
                }
                return ProfileV3TransformEntry(from: from, to: to)
            }
            return ProfileV3TransformTableSummary(id: id, entries: entries)
        }
    }

    public func v3MacroSummaries() throws -> [ProfileV3MacroSummary] {
        try v3Array(named: "macros").compactMap { node in
            guard
                let object = node.objectValue,
                let id = object["id"]?.stringValue
            else {
                return nil
            }
            return ProfileV3MacroSummary(
                id: id,
                actions: (object["actions"]?.arrayValue ?? []).compactMap(Self.v3ActionDraft)
            )
        }
    }

    public mutating func v3SetInitialLayer(_ layerID: String) throws {
        _ = try v3ObjectInArray(named: "layers", id: layerID)
        try v3SetTopLevel("initialLayerRef", .string(layerID))
    }

    public mutating func v3CreateBoard(id: String) throws {
        try Self.v3ValidateSemanticID(id, field: "board.id")
        var top = try v3TopObject()
        var boards = try v3MutableArray(in: top, named: "boards")
        guard !boards.contains(where: { $0.objectValue?["id"]?.stringValue == id }) else {
            throw ProfileAuthoringError.duplicateProfile(id)
        }
        boards.append(.object([
            "id": .string(id),
            "entries": .array([])
        ]))
        top["boards"] = .array(boards)
        root = .object(top)
    }

    public mutating func v3DuplicateBoard(
        sourceBoardID: String,
        newBoardID: String
    ) throws {
        try Self.v3ValidateSemanticID(newBoardID, field: "board.id")
        var top = try v3TopObject()
        var boards = try v3MutableArray(in: top, named: "boards")
        guard !boards.contains(where: {
            $0.objectValue?["id"]?.stringValue == newBoardID
        }) else {
            throw ProfileAuthoringError.duplicateProfile(newBoardID)
        }
        guard let source = boards.first(where: {
            $0.objectValue?["id"]?.stringValue == sourceBoardID
        })?.objectValue else {
            throw ProfileAuthoringError.missingReference(sourceBoardID)
        }

        var copy = source
        copy["id"] = .string(newBoardID)
        if let entries = copy["entries"] {
            copy["entries"] = Self.v3RewriteBoardReferences(
                entries,
                from: sourceBoardID,
                to: newBoardID
            )
        }
        boards.append(.object(copy))
        top["boards"] = .array(boards)
        root = .object(top)
    }

    public mutating func v3DeleteBoard(id: String) throws {
        let refs = try v3InboundReferences(to: id)
        guard refs.isEmpty else {
            throw ProfileAuthoringError.invalidJSON(
                "Board \(id) has \(refs.count) inbound reference(s)"
            )
        }
        var top = try v3TopObject()
        var boards = try v3MutableArray(in: top, named: "boards")
        guard boards.contains(where: { $0.objectValue?["id"]?.stringValue == id }) else {
            throw ProfileAuthoringError.missingReference(id)
        }
        boards.removeAll { $0.objectValue?["id"]?.stringValue == id }
        top["boards"] = .array(boards)
        root = .object(top)
    }

    public mutating func v3CreateLayer(
        id: String,
        name: String?,
        rootBoardID: String
    ) throws {
        try Self.v3ValidateSemanticID(id, field: "layer.id")
        _ = try v3ObjectInArray(named: "boards", id: rootBoardID)

        var top = try v3TopObject()
        var layers = try v3MutableArray(in: top, named: "layers")
        guard !layers.contains(where: { $0.objectValue?["id"]?.stringValue == id }) else {
            throw ProfileAuthoringError.duplicateProfile(id)
        }

        var object: [String: JSONNode] = [
            "id": .string(id),
            "rootBoardRef": .string(rootBoardID)
        ]
        if let name, !name.isEmpty {
            object["name"] = .string(name)
        }
        layers.append(.object(object))
        top["layers"] = .array(layers)
        root = .object(top)
    }

    public mutating func v3RenameLayer(
        id: String,
        name: String?
    ) throws {
        try v3MutateObjectInArray(named: "layers", id: id) { object in
            if let name, !name.isEmpty {
                object["name"] = .string(name)
            } else {
                object.removeValue(forKey: "name")
            }
        }
    }

    public mutating func v3SetLayerRootBoard(
        layerID: String,
        boardID: String
    ) throws {
        _ = try v3ObjectInArray(named: "boards", id: boardID)
        try v3MutateObjectInArray(named: "layers", id: layerID) { object in
            object["rootBoardRef"] = .string(boardID)
        }
    }

    public mutating func v3DuplicateLayer(
        sourceLayerID: String,
        newLayerID: String,
        newName: String?,
        newRootBoardID: String
    ) throws {
        try Self.v3ValidateSemanticID(newLayerID, field: "layer.id")
        try Self.v3ValidateSemanticID(newRootBoardID, field: "board.id")

        var top = try v3TopObject()
        var layers = try v3MutableArray(in: top, named: "layers")
        var boards = try v3MutableArray(in: top, named: "boards")

        guard !layers.contains(where: {
            $0.objectValue?["id"]?.stringValue == newLayerID
        }) else {
            throw ProfileAuthoringError.duplicateProfile(newLayerID)
        }
        guard !boards.contains(where: {
            $0.objectValue?["id"]?.stringValue == newRootBoardID
        }) else {
            throw ProfileAuthoringError.duplicateProfile(newRootBoardID)
        }
        guard let sourceLayer = layers.first(where: {
            $0.objectValue?["id"]?.stringValue == sourceLayerID
        })?.objectValue,
              let sourceRootID = sourceLayer["rootBoardRef"]?.stringValue,
              let sourceBoard = boards.first(where: {
                  $0.objectValue?["id"]?.stringValue == sourceRootID
              })?.objectValue else {
            throw ProfileAuthoringError.missingReference(sourceLayerID)
        }

        var boardCopy = sourceBoard
        boardCopy["id"] = .string(newRootBoardID)
        if let entries = boardCopy["entries"] {
            boardCopy["entries"] = Self.v3RewriteBoardReferences(
                entries,
                from: sourceRootID,
                to: newRootBoardID
            )
        }
        boards.append(.object(boardCopy))

        var layerCopy = sourceLayer
        layerCopy["id"] = .string(newLayerID)
        layerCopy["rootBoardRef"] = .string(newRootBoardID)
        if let newName {
            if newName.isEmpty {
                layerCopy.removeValue(forKey: "name")
            } else {
                layerCopy["name"] = .string(newName)
            }
        }
        layers.append(.object(layerCopy))

        top["boards"] = .array(boards)
        top["layers"] = .array(layers)
        root = .object(top)
    }

    public mutating func v3DeleteLayer(id: String) throws {
        let initial = try v3InitialLayerID()
        guard id != initial else {
            throw ProfileAuthoringError.invalidJSON(
                "Select another initial Layer before deleting \(id)"
            )
        }

        var top = try v3TopObject()
        var layers = try v3MutableArray(in: top, named: "layers")
        guard layers.count > 1 else {
            throw ProfileAuthoringError.invalidJSON("Profile v3 requires at least one Layer")
        }
        guard layers.contains(where: { $0.objectValue?["id"]?.stringValue == id }) else {
            throw ProfileAuthoringError.missingReference(id)
        }
        layers.removeAll { $0.objectValue?["id"]?.stringValue == id }
        top["layers"] = .array(layers)
        root = .object(top)
    }

    public mutating func v3CreateEntry(
        boardID: String,
        id: String,
        rect: ProfileV3Rect,
        resolver: JSONNode? = nil
    ) throws {
        try Self.v3ValidateSemanticID(id, field: "entry.id")
        let resolver = resolver ?? .object([
            "cases": .array([]),
            "default": .object([:])
        ])
        try Self.v3ValidateResolverShape(resolver)

        try v3MutateBoard(id: boardID) { board in
            var entries = board["entries"]?.arrayValue ?? []
            guard !entries.contains(where: { $0.objectValue?["id"]?.stringValue == id }) else {
                throw ProfileAuthoringError.duplicateProfile(id)
            }
            try Self.v3ValidateGeometry(
                entries: entries,
                replacingEntryID: nil,
                candidate: rect
            )
            entries.append(.object([
                "id": .string(id),
                "rect": Self.v3RectNode(rect),
                "resolver": resolver
            ]))
            board["entries"] = .array(entries)
        }
    }

    public mutating func v3DuplicateEntry(
        boardID: String,
        sourceEntryID: String,
        newEntryID: String,
        newRect: ProfileV3Rect
    ) throws {
        try Self.v3ValidateSemanticID(newEntryID, field: "entry.id")
        try v3MutateBoard(id: boardID) { board in
            var entries = board["entries"]?.arrayValue ?? []
            guard !entries.contains(where: {
                $0.objectValue?["id"]?.stringValue == newEntryID
            }) else {
                throw ProfileAuthoringError.duplicateProfile(newEntryID)
            }
            guard var source = entries.first(where: {
                $0.objectValue?["id"]?.stringValue == sourceEntryID
            })?.objectValue else {
                throw ProfileAuthoringError.missingReference(sourceEntryID)
            }
            try Self.v3ValidateGeometry(
                entries: entries,
                replacingEntryID: nil,
                candidate: newRect
            )
            source["id"] = .string(newEntryID)
            source["rect"] = Self.v3RectNode(
                newRect,
                preserving: source["rect"]
            )
            entries.append(.object(source))
            board["entries"] = .array(entries)
        }
    }

    public mutating func v3SetEntryRect(
        boardID: String,
        entryID: String,
        rect: ProfileV3Rect
    ) throws {
        try v3MutateBoard(id: boardID) { board in
            var entries = board["entries"]?.arrayValue ?? []
            guard let index = entries.firstIndex(where: {
                $0.objectValue?["id"]?.stringValue == entryID
            }) else {
                throw ProfileAuthoringError.missingReference(entryID)
            }
            try Self.v3ValidateGeometry(
                entries: entries,
                replacingEntryID: entryID,
                candidate: rect
            )
            var entry = entries[index].objectValue ?? [:]
            entry["rect"] = Self.v3RectNode(
                rect,
                preserving: entry["rect"]
            )
            entries[index] = .object(entry)
            board["entries"] = .array(entries)
        }
    }

    public mutating func v3DeleteEntry(
        boardID: String,
        entryID: String
    ) throws {
        try v3MutateBoard(id: boardID) { board in
            var entries = board["entries"]?.arrayValue ?? []
            guard entries.contains(where: {
                $0.objectValue?["id"]?.stringValue == entryID
            }) else {
                throw ProfileAuthoringError.missingReference(entryID)
            }
            entries.removeAll { $0.objectValue?["id"]?.stringValue == entryID }
            board["entries"] = .array(entries)
        }
    }

    public mutating func v3SetEntryResolver(
        boardID: String,
        entryID: String,
        resolver: JSONNode
    ) throws {
        try Self.v3ValidateResolverShape(resolver)
        try v3MutateEntry(boardID: boardID, entryID: entryID) { entry in
            entry["resolver"] = resolver
        }
    }

    public mutating func v3SetEntryDefaultPresentation(
        boardID: String,
        entryID: String,
        text: String?,
        accessibilityLabel: String?
    ) throws {
        try v3MutateDefaultBehavior(boardID: boardID, entryID: entryID) { behavior in
            var presentation = behavior["presentation"]?.objectValue ?? [:]

            if let text {
                var resolved = presentation["text"]?.objectValue ?? [:]
                resolved["base"] = .string(text)
                if resolved["transforms"] == nil {
                    resolved["transforms"] = .array([])
                }
                presentation["text"] = .object(resolved)
            } else {
                presentation.removeValue(forKey: "text")
            }

            if let accessibilityLabel, !accessibilityLabel.isEmpty {
                presentation["accessibilityLabel"] = .string(accessibilityLabel)
            } else {
                presentation.removeValue(forKey: "accessibilityLabel")
            }

            if presentation.isEmpty {
                behavior.removeValue(forKey: "presentation")
            } else {
                behavior["presentation"] = .object(presentation)
            }
        }
    }

    public mutating func v3SetEntryDefaultActions(
        boardID: String,
        entryID: String,
        actions: [ProfileActionDraft]
    ) throws {
        try v3MutateDefaultBehavior(boardID: boardID, entryID: entryID) { behavior in
            behavior["onRelease"] = .array(actions.map(Self.v3ActionNode))
        }
    }

    public mutating func v3SetEntryDefaultTransition(
        boardID: String,
        entryID: String,
        transition: ProfileV3TransitionDraft?
    ) throws {
        if let transition {
            _ = try v3ObjectInArray(named: "boards", id: transition.targetBoardID)
        }
        try v3MutateDefaultBehavior(boardID: boardID, entryID: entryID) { behavior in
            if let transition {
                behavior["transition"] = Self.v3TransitionNode(transition)
            } else {
                behavior.removeValue(forKey: "transition")
            }
        }
    }

    public mutating func v3SetEntryDefaultHold(
        boardID: String,
        entryID: String,
        hold: ProfileV3HoldDraft?
    ) throws {
        if let transition = hold?.transition {
            _ = try v3ObjectInArray(named: "boards", id: transition.targetBoardID)
        }

        try v3MutateDefaultBehavior(boardID: boardID, entryID: entryID) { behavior in
            guard let hold else {
                behavior.removeValue(forKey: "hold")
                return
            }

            guard (50...5000).contains(hold.delayMs) else {
                throw ProfileAuthoringError.invalidJSON(
                    "Hold delayMs must be within 50...5000"
                )
            }

            let repeatActions = hold.repeatBehavior?.actions ?? []
            let releaseCount = behavior["onRelease"]?.arrayValue?.count ?? 0
            let totalActions = releaseCount + hold.onStart.count + repeatActions.count
            guard totalActions <= 16 else {
                throw ProfileAuthoringError.invalidJSON(
                    "Endpoint exceeds 16 Actions across release/Hold/repeat"
                )
            }

            if let repeating = hold.repeatBehavior,
               !(16...5000).contains(repeating.intervalMs) {
                throw ProfileAuthoringError.invalidJSON(
                    "Hold repeat intervalMs must be within 16...5000"
                )
            }

            var object = behavior["hold"]?.objectValue ?? [:]
            object["delayMs"] = .integer(Int64(hold.delayMs))
            object["onStart"] = .array(hold.onStart.map(Self.v3ActionNode))
            object["suppressOnReleaseAfterStart"] = .bool(
                hold.suppressOnReleaseAfterStart
            )

            if let transition = hold.transition {
                object["transition"] = Self.v3TransitionNode(transition)
            } else {
                object.removeValue(forKey: "transition")
            }

            if let repeating = hold.repeatBehavior {
                object["repeat"] = .object([
                    "intervalMs": .integer(Int64(repeating.intervalMs)),
                    "actions": .array(repeating.actions.map(Self.v3ActionNode))
                ])
            } else {
                object.removeValue(forKey: "repeat")
            }

            behavior["hold"] = .object(object)
        }
    }

    public mutating func v3UpsertBooleanState(
        id: String,
        defaultValue: Bool
    ) throws {
        try Self.v3ValidateSemanticID(id, field: "state.id")
        try v3UpsertTopLevelObject(
            arrayName: "states",
            id: id,
            replacement: .object([
                "id": .string(id),
                "type": .string("boolean"),
                "default": .bool(defaultValue)
            ])
        )
        try v3MutateObjectInArray(named: "states", id: id) { object in
            // "values" is semantic enum data rather than an unknown extension
            // member, so it must not survive an enum -> boolean type change.
            object.removeValue(forKey: "values")
        }
    }

    public mutating func v3UpsertEnumState(
        id: String,
        values: [String],
        defaultValue: String
    ) throws {
        try Self.v3ValidateSemanticID(id, field: "state.id")
        guard !values.isEmpty,
              values.count <= 32,
              Set(values).count == values.count,
              values.contains(defaultValue) else {
            throw ProfileAuthoringError.invalidJSON("Invalid enum state \(id)")
        }
        try v3UpsertTopLevelObject(
            arrayName: "states",
            id: id,
            replacement: .object([
                "id": .string(id),
                "type": .string("enum"),
                "values": .array(values.map(JSONNode.string)),
                "default": .string(defaultValue)
            ])
        )
    }

    public mutating func v3DeleteState(id: String) throws {
        try v3DeleteTopLevelObject(arrayName: "states", id: id)
    }

    public mutating func v3UpsertTransformTable(
        id: String,
        entries: [ProfileV3TransformEntry]
    ) throws {
        try Self.v3ValidateSemanticID(id, field: "transformTable.id")
        guard entries.count <= 2048 else {
            throw ProfileAuthoringError.invalidJSON("Transform table exceeds 2048 entries")
        }
        var seen = Set<String>()
        for entry in entries {
            guard !entry.from.isEmpty else {
                throw ProfileAuthoringError.invalidJSON("Transform source must not be empty")
            }
            guard seen.insert(entry.from).inserted else {
                throw ProfileAuthoringError.invalidJSON(
                    "Duplicate transform source: \(entry.from)"
                )
            }
        }
        try v3UpsertTopLevelObject(
            arrayName: "transformTables",
            id: id,
            replacement: .object([
                "id": .string(id),
                "entries": .array(entries.map {
                    .object([
                        "from": .string($0.from),
                        "to": .string($0.to)
                    ])
                })
            ])
        )
    }

    public mutating func v3DeleteTransformTable(id: String) throws {
        try v3DeleteTopLevelObject(arrayName: "transformTables", id: id)
    }

    public mutating func v3UpsertMacro(
        id: String,
        actions: [ProfileActionDraft]
    ) throws {
        try Self.v3ValidateSemanticID(id, field: "macro.id")
        guard actions.count <= 32 else {
            throw ProfileAuthoringError.invalidJSON("Macro exceeds 32 Actions")
        }
        try v3UpsertTopLevelObject(
            arrayName: "macros",
            id: id,
            replacement: .object([
                "id": .string(id),
                "actions": .array(actions.map(Self.v3ActionNode))
            ])
        )
    }

    public mutating func v3DeleteMacro(id: String) throws {
        try v3DeleteTopLevelObject(arrayName: "macros", id: id)
    }

    public func v3SemanticSectionNode(
        _ section: ProfileV3SemanticSection
    ) throws -> JSONNode {
        let top = try v3TopObject()
        guard let node = top[section.rawValue], node.arrayValue != nil else {
            throw ProfileAuthoringError.missingField(section.rawValue)
        }
        return node
    }

    public mutating func v3SetSemanticSectionNode(
        _ section: ProfileV3SemanticSection,
        node: JSONNode
    ) throws {
        guard node.arrayValue != nil else {
            throw ProfileAuthoringError.invalidJSON(
                "\(section.rawValue) must be a JSON array"
            )
        }
        try v3SetTopLevel(section.rawValue, node)
    }

    // MARK: - Internal v3 helpers

    private func v3TopObject() throws -> [String: JSONNode] {
        guard isProfileV3 else {
            throw ProfileAuthoringError.invalidJSON(
                "Profile v3 operation requires gesture-ime.profile.v3"
            )
        }
        guard let object = root.objectValue else {
            throw ProfileAuthoringError.invalidJSON("Profile root must be an object")
        }
        return object
    }

    private mutating func v3SetTopLevel(
        _ key: String,
        _ value: JSONNode
    ) throws {
        var object = try v3TopObject()
        object[key] = value
        root = .object(object)
    }

    private func v3Array(named name: String) throws -> [JSONNode] {
        let object = try v3TopObject()
        guard let array = object[name]?.arrayValue else {
            throw ProfileAuthoringError.missingField(name)
        }
        return array
    }

    private func v3MutableArray(
        in object: [String: JSONNode],
        named name: String
    ) throws -> [JSONNode] {
        guard let array = object[name]?.arrayValue else {
            throw ProfileAuthoringError.missingField(name)
        }
        return array
    }

    private func v3ObjectInArray(
        named name: String,
        id: String
    ) throws -> [String: JSONNode] {
        guard let object = try v3Array(named: name)
            .first(where: { $0.objectValue?["id"]?.stringValue == id })?
            .objectValue else {
            throw ProfileAuthoringError.missingReference(id)
        }
        return object
    }

    private func v3EntryObject(
        boardID: String,
        entryID: String
    ) throws -> [String: JSONNode] {
        let board = try v3ObjectInArray(named: "boards", id: boardID)
        guard let entry = (board["entries"]?.arrayValue ?? [])
            .first(where: { $0.objectValue?["id"]?.stringValue == entryID })?
            .objectValue else {
            throw ProfileAuthoringError.missingReference(entryID)
        }
        return entry
    }

    private mutating func v3MutateObjectInArray(
        named name: String,
        id: String,
        mutation: (inout [String: JSONNode]) throws -> Void
    ) throws {
        var top = try v3TopObject()
        var items = try v3MutableArray(in: top, named: name)
        guard let index = items.firstIndex(where: {
            $0.objectValue?["id"]?.stringValue == id
        }) else {
            throw ProfileAuthoringError.missingReference(id)
        }
        var object = items[index].objectValue ?? [:]
        try mutation(&object)
        items[index] = .object(object)
        top[name] = .array(items)
        root = .object(top)
    }

    private mutating func v3MutateBoard(
        id: String,
        mutation: (inout [String: JSONNode]) throws -> Void
    ) throws {
        try v3MutateObjectInArray(named: "boards", id: id, mutation: mutation)
    }

    private mutating func v3MutateEntry(
        boardID: String,
        entryID: String,
        mutation: (inout [String: JSONNode]) throws -> Void
    ) throws {
        try v3MutateBoard(id: boardID) { board in
            var entries = board["entries"]?.arrayValue ?? []
            guard let index = entries.firstIndex(where: {
                $0.objectValue?["id"]?.stringValue == entryID
            }) else {
                throw ProfileAuthoringError.missingReference(entryID)
            }
            var entry = entries[index].objectValue ?? [:]
            try mutation(&entry)
            entries[index] = .object(entry)
            board["entries"] = .array(entries)
        }
    }

    private mutating func v3MutateDefaultBehavior(
        boardID: String,
        entryID: String,
        mutation: (inout [String: JSONNode]) throws -> Void
    ) throws {
        try v3MutateEntry(boardID: boardID, entryID: entryID) { entry in
            guard var resolver = entry["resolver"]?.objectValue else {
                throw ProfileAuthoringError.missingField("resolver")
            }
            guard var behavior = resolver["default"]?.objectValue else {
                throw ProfileAuthoringError.missingField("resolver.default")
            }
            try mutation(&behavior)
            resolver["default"] = .object(behavior)
            entry["resolver"] = .object(resolver)
        }
    }

    private mutating func v3UpsertTopLevelObject(
        arrayName: String,
        id: String,
        replacement: JSONNode
    ) throws {
        var top = try v3TopObject()
        var items = try v3MutableArray(in: top, named: arrayName)
        if let index = items.firstIndex(where: {
            $0.objectValue?["id"]?.stringValue == id
        }) {
            // Preserve unknown ordinary fields for edited definitions.
            var merged = items[index].objectValue ?? [:]
            for (key, value) in replacement.objectValue ?? [:] {
                merged[key] = value
            }
            items[index] = .object(merged)
        } else {
            items.append(replacement)
        }
        top[arrayName] = .array(items)
        root = .object(top)
    }

    private mutating func v3DeleteTopLevelObject(
        arrayName: String,
        id: String
    ) throws {
        var top = try v3TopObject()
        var items = try v3MutableArray(in: top, named: arrayName)
        guard items.contains(where: { $0.objectValue?["id"]?.stringValue == id }) else {
            throw ProfileAuthoringError.missingReference(id)
        }
        items.removeAll { $0.objectValue?["id"]?.stringValue == id }
        top[arrayName] = .array(items)
        root = .object(top)
    }

    private func v3AllBoardReferences() throws -> [ProfileV3BoardReference] {
        var result: [ProfileV3BoardReference] = []

        for layer in try v3Array(named: "layers") {
            guard
                let object = layer.objectValue,
                let layerID = object["id"]?.stringValue,
                let target = object["rootBoardRef"]?.stringValue
            else {
                continue
            }
            result.append(
                ProfileV3BoardReference(
                    kind: .layerRoot,
                    targetBoardID: target,
                    layerID: layerID,
                    path: "layers.\(layerID).rootBoardRef"
                )
            )
        }

        for boardNode in try v3Array(named: "boards") {
            guard
                let board = boardNode.objectValue,
                let boardID = board["id"]?.stringValue
            else {
                continue
            }

            for entryNode in board["entries"]?.arrayValue ?? [] {
                guard
                    let entry = entryNode.objectValue,
                    let entryID = entry["id"]?.stringValue,
                    let resolver = entry["resolver"]?.objectValue
                else {
                    continue
                }

                if let defaultBehavior = resolver["default"]?.objectValue {
                    Self.v3CollectBehaviorReferences(
                        defaultBehavior,
                        boardID: boardID,
                        entryID: entryID,
                        path: "boards.\(boardID).entries.\(entryID).resolver.default",
                        into: &result
                    )
                }

                for (index, caseNode) in (resolver["cases"]?.arrayValue ?? []).enumerated() {
                    guard let behavior = caseNode.objectValue?["behavior"]?.objectValue else {
                        continue
                    }
                    Self.v3CollectBehaviorReferences(
                        behavior,
                        boardID: boardID,
                        entryID: entryID,
                        path: "boards.\(boardID).entries.\(entryID).resolver.cases[\(index)].behavior",
                        into: &result
                    )
                }
            }
        }

        return result
    }

    private static func v3CollectBehaviorReferences(
        _ behavior: [String: JSONNode],
        boardID: String,
        entryID: String,
        path: String,
        into result: inout [ProfileV3BoardReference]
    ) {
        if let target = behavior["transition"]?.objectValue?["targetBoardRef"]?.stringValue {
            result.append(
                ProfileV3BoardReference(
                    kind: .entryTransition,
                    targetBoardID: target,
                    sourceBoardID: boardID,
                    sourceEntryID: entryID,
                    path: path + ".transition"
                )
            )
        }

        if let target = behavior["hold"]?.objectValue?["transition"]?
            .objectValue?["targetBoardRef"]?.stringValue {
            result.append(
                ProfileV3BoardReference(
                    kind: .holdTransition,
                    targetBoardID: target,
                    sourceBoardID: boardID,
                    sourceEntryID: entryID,
                    path: path + ".hold.transition"
                )
            )
        }
    }

    private static func v3EntrySummary(_ node: JSONNode) -> ProfileV3BoardEntrySummary? {
        guard
            let object = node.objectValue,
            let id = object["id"]?.stringValue,
            let rect = v3Rect(from: object["rect"]),
            let resolver = object["resolver"]?.objectValue,
            let defaultBehavior = resolver["default"]?.objectValue
        else {
            return nil
        }

        let presentation = defaultBehavior["presentation"]?.objectValue
        let text = presentation?["text"]?.objectValue?["base"]?.stringValue
        let accessibility = presentation?["accessibilityLabel"]?.stringValue
        let actions = (defaultBehavior["onRelease"]?.arrayValue ?? []).compactMap(v3ActionDraft)
        let transition = defaultBehavior["transition"].flatMap(v3TransitionDraft)
        let hold = defaultBehavior["hold"].flatMap(v3HoldSummary)

        return ProfileV3BoardEntrySummary(
            id: id,
            rect: rect,
            presentationText: text,
            accessibilityLabel: accessibility,
            caseCount: resolver["cases"]?.arrayValue?.count ?? 0,
            onRelease: actions,
            transition: transition,
            hold: hold
        )
    }

    private static func v3HoldSummary(_ node: JSONNode) -> ProfileV3HoldSummary? {
        guard
            let object = node.objectValue,
            let delay = object["delayMs"]?.intValue,
            let suppress = object["suppressOnReleaseAfterStart"]?.boolValue
        else {
            return nil
        }

        let repeating = object["repeat"]?.objectValue
        return ProfileV3HoldSummary(
            delayMs: delay,
            onStart: (object["onStart"]?.arrayValue ?? []).compactMap(v3ActionDraft),
            transition: object["transition"].flatMap(v3TransitionDraft),
            repeatIntervalMs: repeating?["intervalMs"]?.intValue,
            repeatActions: (repeating?["actions"]?.arrayValue ?? []).compactMap(v3ActionDraft),
            suppressOnReleaseAfterStart: suppress
        )
    }

    private static func v3ActionDraft(_ node: JSONNode) -> ProfileActionDraft? {
        guard
            let object = node.objectValue,
            let actionID = object["actionID"]?.stringValue,
            let arguments = object["arguments"]?.objectValue
        else {
            return nil
        }
        return ProfileActionDraft(actionID: actionID, arguments: arguments)
    }

    private static func v3ActionNode(_ action: ProfileActionDraft) -> JSONNode {
        .object([
            "actionID": .string(action.actionID),
            "arguments": .object(action.arguments)
        ])
    }

    private static func v3TransitionDraft(_ node: JSONNode) -> ProfileV3TransitionDraft? {
        guard
            let object = node.objectValue,
            let target = object["targetBoardRef"]?.stringValue,
            let lifetimeRaw = object["lifetime"]?.stringValue,
            let lifetime = ProfileV3TransitionLifetime(rawValue: lifetimeRaw)
        else {
            return nil
        }
        return ProfileV3TransitionDraft(
            targetBoardID: target,
            lifetime: lifetime
        )
    }

    private static func v3TransitionNode(
        _ transition: ProfileV3TransitionDraft
    ) -> JSONNode {
        .object([
            "targetBoardRef": .string(transition.targetBoardID),
            "lifetime": .string(transition.lifetime.rawValue)
        ])
    }

    private static func v3Rect(from node: JSONNode?) -> ProfileV3Rect? {
        guard
            let object = node?.objectValue,
            let x = object["x"]?.intValue,
            let y = object["y"]?.intValue,
            let width = object["width"]?.intValue,
            let height = object["height"]?.intValue
        else {
            return nil
        }
        return ProfileV3Rect(x: x, y: y, width: width, height: height)
    }

    private static func v3RectNode(
        _ rect: ProfileV3Rect,
        preserving existing: JSONNode? = nil
    ) -> JSONNode {
        var object = existing?.objectValue ?? [:]
        object["x"] = .integer(Int64(rect.x))
        object["y"] = .integer(Int64(rect.y))
        object["width"] = .integer(Int64(rect.width))
        object["height"] = .integer(Int64(rect.height))
        return .object(object)
    }

    private static func v3ValidateResolverShape(_ node: JSONNode) throws {
        guard
            let object = node.objectValue,
            object["cases"]?.arrayValue != nil,
            object["default"]?.objectValue != nil
        else {
            throw ProfileAuthoringError.invalidJSON(
                "Profile v3 resolver requires cases[] and default object"
            )
        }
    }

    private static func v3ValidateGeometry(
        entries: [JSONNode],
        replacingEntryID: String?,
        candidate: ProfileV3Rect
    ) throws {
        guard candidate.width >= 1,
              candidate.width <= 20,
              candidate.height >= 1,
              candidate.height <= 20,
              (-20...20).contains(candidate.x),
              (-20...20).contains(candidate.y),
              (-20...20).contains(candidate.maxX),
              (-20...20).contains(candidate.maxY) else {
            throw ProfileAuthoringError.invalidJSON(
                "Board rect is outside canonical v3 bounds"
            )
        }

        var rects: [ProfileV3Rect] = [candidate]
        for entry in entries {
            guard let object = entry.objectValue else { continue }
            if let replacingEntryID,
               object["id"]?.stringValue == replacingEntryID {
                continue
            }
            guard let rect = v3Rect(from: object["rect"]) else { continue }
            if candidate.overlapsPositiveArea(rect) {
                throw ProfileAuthoringError.invalidJSON(
                    "Board rect overlaps entry \(object["id"]?.stringValue ?? "?")"
                )
            }
            rects.append(rect)
        }

        guard let minX = rects.map(\.x).min(),
              let minY = rects.map(\.y).min(),
              let maxX = rects.map(\.maxX).max(),
              let maxY = rects.map(\.maxY).max(),
              maxX - minX <= 20,
              maxY - minY <= 20 else {
            throw ProfileAuthoringError.invalidJSON(
                "Board occupied extent exceeds 20×20 atomic units"
            )
        }
    }

    private static func v3ValidateSemanticID(
        _ value: String,
        field: String
    ) throws {
        guard !value.isEmpty, value.utf8.count <= 128 else {
            throw ProfileAuthoringError.invalidJSON("\(field) is invalid")
        }
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._-")
        )
        guard let first = value.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first),
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ProfileAuthoringError.invalidJSON("\(field) is invalid")
        }
    }

    private static func v3RewriteBoardReferences(
        _ node: JSONNode,
        from source: String,
        to target: String
    ) -> JSONNode {
        switch node {
        case .object(let object):
            var next = object
            if next["targetBoardRef"]?.stringValue == source {
                next["targetBoardRef"] = .string(target)
            }
            return .object(
                next.mapValues {
                    v3RewriteBoardReferences($0, from: source, to: target)
                }
            )
        case .array(let array):
            return .array(
                array.map {
                    v3RewriteBoardReferences($0, from: source, to: target)
                }
            )
        default:
            return node
        }
    }
}

private extension JSONNode {
    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}
