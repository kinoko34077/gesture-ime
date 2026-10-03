import Foundation

public struct ProfileDocument: Equatable, Sendable {
    private var root: JSONNode

    public init(data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        let node = try JSONNode(foundation: object)
        guard case .object = node else {
            throw ProfileAuthoringError.invalidJSON("Profile root must be an object")
        }
        self.root = node
    }

    public init(jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw ProfileAuthoringError.invalidJSON("Profile is not UTF-8")
        }
        try self.init(data: data)
    }

    public var summary: ProfileSummary {
        let object = root.objectValue ?? [:]
        return ProfileSummary(
            id: object["id"]?.stringValue ?? "",
            name: object["name"]?.stringValue ?? "",
            version: object["version"]?.intValue ?? 0
        )
    }

    public func encoded(pretty: Bool = true) throws -> Data {
        let options: JSONSerialization.WritingOptions = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return try JSONSerialization.data(withJSONObject: root.foundationValue, options: options)
    }

    public mutating func rename(_ name: String) throws {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw ProfileAuthoringError.missingField("name")
        }
        try setTopLevel("name", .string(value))
    }

    public mutating func cloneIdentity(id: String, name: String) throws {
        let cleanID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { throw ProfileAuthoringError.missingField("id") }
        guard !cleanName.isEmpty else { throw ProfileAuthoringError.missingField("name") }
        try setTopLevel("id", .string(cleanID))
        try setTopLevel("name", .string(cleanName))
        try setTopLevel("version", .integer(1))
    }

    public func gesturePolicy() throws -> ProfileGesturePolicy {
        let object = try topObject()
        guard let policy = object["gesturePolicy"]?.objectValue else {
            throw ProfileAuthoringError.missingField("gesturePolicy")
        }
        guard
            let deadZone = policy["deadZone"]?.doubleValue,
            let stage1 = policy["stage1CommitDistance"]?.doubleValue,
            let stage2 = policy["stage2CommitDistance"]?.doubleValue,
            let hysteresis = policy["angularHysteresisDegrees"]?.doubleValue,
            let stages = policy["maxDirectionalStages"]?.intValue
        else {
            throw ProfileAuthoringError.invalidJSON("Invalid gesturePolicy")
        }
        return ProfileGesturePolicy(
            deadZone: deadZone,
            stage1CommitDistance: stage1,
            stage2CommitDistance: stage2,
            angularHysteresisDegrees: hysteresis,
            maxDirectionalStages: stages
        )
    }

    public mutating func setGesturePolicy(_ policy: ProfileGesturePolicy) throws {
        var rootObject = try topObject()
        var object = rootObject["gesturePolicy"]?.objectValue ?? [:]
        object["deadZone"] = .decimal(policy.deadZone)
        object["stage1CommitDistance"] = .decimal(policy.stage1CommitDistance)
        object["stage2CommitDistance"] = .decimal(policy.stage2CommitDistance)
        object["angularHysteresisDegrees"] = .decimal(policy.angularHysteresisDegrees)
        object["maxDirectionalStages"] = .integer(Int64(policy.maxDirectionalStages))
        rootObject["gesturePolicy"] = .object(object)
        root = .object(rootObject)
    }

    public func layerIDs() throws -> [String] {
        try array(named: "layers").compactMap { $0.objectValue?["id"]?.stringValue }
    }

    public func keys(layerID: String) throws -> [ProfileKeySummary] {
        let references = try layerReferences(layerID: layerID)
        let layout = try objectInArray(named: "layouts", id: references.layoutRef)
        let placements = layout["placements"]?.arrayValue ?? []
        let definitions = try array(named: "keyDefinitions")
        let definitionMap = Dictionary(
            uniqueKeysWithValues: definitions.compactMap { node -> (String, [String: JSONNode])? in
                guard let object = node.objectValue, let id = object["id"]?.stringValue else { return nil }
                return (id, object)
            }
        )

        return placements.compactMap { node in
            guard
                let placement = node.objectValue,
                let keyID = placement["keyID"]?.stringValue,
                let row = placement["row"]?.intValue,
                let column = placement["column"]?.intValue
            else { return nil }

            let definition = definitionMap[keyID]
            let title = definition?["presentation"]?.objectValue?["text"]?.stringValue ?? keyID
            return ProfileKeySummary(
                id: keyID,
                title: title,
                role: definition?["role"]?.stringValue,
                row: row,
                column: column,
                width: placement["width"]?.doubleValue ?? 1,
                height: placement["height"]?.doubleValue ?? 1
            )
        }
    }

    public func bindings(layerID: String, keyID: String) throws -> [ProfileBindingSummary] {
        let references = try layerReferences(layerID: layerID)
        let bindingSet = try objectInArray(named: "bindingSets", id: references.bindingSetRef)
        let bindings = bindingSet["bindings"]?.arrayValue ?? []

        return bindings.compactMap { node in
            guard
                let object = node.objectValue,
                object["keyID"]?.stringValue == keyID,
                let pathNodes = object["path"]?.arrayValue,
                let behavior = object["behavior"]?.objectValue
            else { return nil }

            let path = pathNodes.compactMap { token -> ProfileDirection? in
                guard let raw = token.objectValue?["direction"]?.stringValue else { return nil }
                return ProfileDirection(rawValue: raw)
            }
            guard path.count == pathNodes.count else { return nil }

            let actions = (behavior["onRelease"]?.arrayValue ?? []).compactMap(Self.actionDraft)
            let presentation = behavior["presentation"]?.objectValue?["text"]?.stringValue
            return ProfileBindingSummary(
                keyID: keyID,
                path: path,
                presentationText: presentation,
                actions: actions
            )
        }
        .sorted { lhs, rhs in
            let l = lhs.path.map(\.rawValue).joined(separator: ",")
            let r = rhs.path.map(\.rawValue).joined(separator: ",")
            if lhs.path.count != rhs.path.count { return lhs.path.count < rhs.path.count }
            return l < r
        }
    }

    public mutating func setKeyPresentation(keyID: String, text: String) throws {
        var rootObject = try topObject()
        var definitions = try mutableArray(in: rootObject, named: "keyDefinitions")
        guard let index = definitions.firstIndex(where: { $0.objectValue?["id"]?.stringValue == keyID }) else {
            throw ProfileAuthoringError.missingReference(keyID)
        }

        var definition = definitions[index].objectValue ?? [:]
        var presentation = definition["presentation"]?.objectValue ?? [:]
        presentation["text"] = .string(text)
        definition["presentation"] = .object(presentation)
        definitions[index] = .object(definition)
        rootObject["keyDefinitions"] = .array(definitions)
        root = .object(rootObject)
    }

    public mutating func setPlacement(
        layerID: String,
        keyID: String,
        row: Int,
        column: Int,
        width: Double,
        height: Double
    ) throws {
        let references = try layerReferences(layerID: layerID)
        var rootObject = try topObject()
        var layouts = try mutableArray(in: rootObject, named: "layouts")
        guard let layoutIndex = layouts.firstIndex(where: { $0.objectValue?["id"]?.stringValue == references.layoutRef }) else {
            throw ProfileAuthoringError.missingReference(references.layoutRef)
        }

        var layout = layouts[layoutIndex].objectValue ?? [:]
        var placements = layout["placements"]?.arrayValue ?? []
        guard let placementIndex = placements.firstIndex(where: { $0.objectValue?["keyID"]?.stringValue == keyID }) else {
            throw ProfileAuthoringError.missingReference(keyID)
        }

        var placement = placements[placementIndex].objectValue ?? [:]
        placement["row"] = .integer(Int64(row))
        placement["column"] = .integer(Int64(column))
        placement["width"] = Self.number(width)
        placement["height"] = Self.number(height)
        placements[placementIndex] = .object(placement)
        layout["placements"] = .array(placements)
        layouts[layoutIndex] = .object(layout)
        rootObject["layouts"] = .array(layouts)
        root = .object(rootObject)
    }

    public mutating func upsertBinding(
        layerID: String,
        keyID: String,
        path: [ProfileDirection],
        presentationText: String?,
        actions: [ProfileActionDraft]
    ) throws {
        guard path.count <= 2 else {
            throw ProfileAuthoringError.invalidPath("v1 supports at most two directional stages")
        }

        let references = try layerReferences(layerID: layerID)
        var rootObject = try topObject()
        var sets = try mutableArray(in: rootObject, named: "bindingSets")
        guard let setIndex = sets.firstIndex(where: { $0.objectValue?["id"]?.stringValue == references.bindingSetRef }) else {
            throw ProfileAuthoringError.missingReference(references.bindingSetRef)
        }

        var set = sets[setIndex].objectValue ?? [:]
        var bindings = set["bindings"]?.arrayValue ?? []
        let pathNode = JSONNode.array(path.map { .object(["direction": .string($0.rawValue)]) })

        let existingIndex = bindings.firstIndex { node in
            guard let object = node.objectValue, object["keyID"]?.stringValue == keyID else { return false }
            return object["path"] == pathNode
        }

        var binding = existingIndex.flatMap { bindings[$0].objectValue } ?? [:]
        binding["keyID"] = .string(keyID)
        binding["path"] = pathNode

        var behavior = binding["behavior"]?.objectValue ?? [:]
        if let presentationText {
            var presentation = behavior["presentation"]?.objectValue ?? [:]
            presentation["text"] = .string(presentationText)
            behavior["presentation"] = .object(presentation)
        }
        behavior["onRelease"] = .array(actions.map(Self.actionNode))
        binding["behavior"] = .object(behavior)

        if let existingIndex {
            bindings[existingIndex] = .object(binding)
        } else {
            bindings.append(.object(binding))
        }

        set["bindings"] = .array(bindings)
        sets[setIndex] = .object(set)
        rootObject["bindingSets"] = .array(sets)
        root = .object(rootObject)
    }

    public mutating func removeBinding(
        layerID: String,
        keyID: String,
        path: [ProfileDirection]
    ) throws {
        let references = try layerReferences(layerID: layerID)
        var rootObject = try topObject()
        var sets = try mutableArray(in: rootObject, named: "bindingSets")
        guard let setIndex = sets.firstIndex(where: { $0.objectValue?["id"]?.stringValue == references.bindingSetRef }) else {
            throw ProfileAuthoringError.missingReference(references.bindingSetRef)
        }

        var set = sets[setIndex].objectValue ?? [:]
        let pathNode = JSONNode.array(path.map { .object(["direction": .string($0.rawValue)]) })
        var bindings = set["bindings"]?.arrayValue ?? []
        bindings.removeAll { node in
            guard let object = node.objectValue else { return false }
            return object["keyID"]?.stringValue == keyID && object["path"] == pathNode
        }
        set["bindings"] = .array(bindings)
        sets[setIndex] = .object(set)
        rootObject["bindingSets"] = .array(sets)
        root = .object(rootObject)
    }

    private func topObject() throws -> [String: JSONNode] {
        guard let object = root.objectValue else {
            throw ProfileAuthoringError.invalidJSON("Profile root must be an object")
        }
        return object
    }

    private mutating func setTopLevel(_ key: String, _ value: JSONNode) throws {
        var object = try topObject()
        object[key] = value
        root = .object(object)
    }

    private func array(named name: String) throws -> [JSONNode] {
        let object = try topObject()
        guard let array = object[name]?.arrayValue else {
            throw ProfileAuthoringError.missingField(name)
        }
        return array
    }

    private func mutableArray(in object: [String: JSONNode], named name: String) throws -> [JSONNode] {
        guard let array = object[name]?.arrayValue else {
            throw ProfileAuthoringError.missingField(name)
        }
        return array
    }

    private func objectInArray(named name: String, id: String) throws -> [String: JSONNode] {
        guard let object = try array(named: name)
            .first(where: { $0.objectValue?["id"]?.stringValue == id })?
            .objectValue
        else {
            throw ProfileAuthoringError.missingReference(id)
        }
        return object
    }

    private func layerReferences(layerID: String) throws -> (layoutRef: String, bindingSetRef: String) {
        let layer = try objectInArray(named: "layers", id: layerID)
        guard
            let layoutRef = layer["layoutRef"]?.stringValue,
            let bindingSetRef = layer["bindingSetRef"]?.stringValue
        else {
            throw ProfileAuthoringError.invalidJSON("Layer \(layerID) is missing references")
        }
        return (layoutRef, bindingSetRef)
    }

    private static func actionDraft(_ node: JSONNode) -> ProfileActionDraft? {
        guard
            let object = node.objectValue,
            let id = object["actionID"]?.stringValue,
            let arguments = object["arguments"]?.objectValue
        else { return nil }
        return ProfileActionDraft(actionID: id, arguments: arguments)
    }

    private static func actionNode(_ action: ProfileActionDraft) -> JSONNode {
        .object([
            "actionID": .string(action.actionID),
            "arguments": .object(action.arguments)
        ])
    }

    private static func number(_ value: Double) -> JSONNode {
        value.rounded() == value ? .integer(Int64(value)) : .decimal(value)
    }
}
