import Foundation

public enum ProfileValidationCode: String, Codable, Sendable {
    case profileTooLarge = "E_PROFILE_TOO_LARGE"
    case unsupportedSchema = "E_UNSUPPORTED_SCHEMA"
    case limitKeys = "E_LIMIT_KEYS"
    case limitLayouts = "E_LIMIT_LAYOUTS"
    case limitPlacements = "E_LIMIT_PLACEMENTS"
    case limitLayers = "E_LIMIT_LAYERS"
    case limitBindingSets = "E_LIMIT_BINDING_SETS"
    case limitBindingsPerKey = "E_LIMIT_BINDINGS_PER_KEY"
    case limitBindingsTotal = "E_LIMIT_BINDINGS_TOTAL"
    case limitTrieNodes = "E_LIMIT_TRIE_NODES"
    case pathDepth = "E_PATH_DEPTH"
    case limitMacros = "E_LIMIT_MACROS"
    case limitActions = "E_LIMIT_ACTIONS"
    case argumentTooLarge = "E_ARGUMENT_TOO_LARGE"
    case limitLayerStack = "E_LIMIT_LAYER_STACK"
    case duplicateID = "E_DUPLICATE_ID"
    case missingReference = "E_MISSING_REFERENCE"
    case duplicateBindingPath = "E_DUPLICATE_BINDING_PATH"
    case unknownAction = "E_UNKNOWN_ACTION"
    case invalidActionArguments = "E_INVALID_ACTION_ARGUMENTS"
    case macroNesting = "E_MACRO_NESTING"
    case invalidGesturePolicy = "E_INVALID_GESTURE_POLICY"
}

public struct ProfileValidationError: Error, Equatable, Sendable {
    public var code: ProfileValidationCode
    public var detail: String?
    public init(_ code: ProfileValidationCode, _ detail: String? = nil) {
        self.code = code; self.detail = detail
    }
}

public enum ProfileLimits {
    public static let encodedBytes = 1_048_576
    public static let keys = 256
    public static let layouts = 32
    public static let placementsPerLayout = 256
    public static let layers = 32
    public static let bindingSets = 64
    public static let bindingsPerKey = 128
    public static let bindingsTotal = 8192
    public static let trieNodes = 16384
    public static let pathDepth = 2
    public static let macros = 128
    public static let endpointActions = 16
    public static let macroActions = 32
    public static let stringArgumentBytes = 4096
    public static let argumentsBytes = 16384
    public static let layerStackDepth = 16
}

public enum ProfileCodec {
    public static func decodeAndValidate(_ data: Data) throws -> ProfileBundle {
        guard data.count <= ProfileLimits.encodedBytes else {
            throw ProfileValidationError(.profileTooLarge)
        }
        let profile: ProfileBundle
        do {
            profile = try JSONDecoder().decode(ProfileBundle.self, from: data)
        } catch {
            throw ProfileValidationError(.unsupportedSchema, String(describing: error))
        }
        try ProfileValidator.validate(profile, encodedBytes: data.count)
        return profile
    }
}

public enum ProfileValidator {
    private static let commonActions: Set<String> = [
        "noop", "text.insert", "text.directInsert", "edit.delete", "cursor.move",
        "layer.set", "layer.push", "layer.pop", "profile.switch", "conversion.commit",
        "conversion.selectCandidate", "panel.open", "macro.run",
        "system.nextKeyboard", "system.dismissKeyboard"
    ]

    public static func validate(_ profile: ProfileBundle, encodedBytes: Int? = nil) throws {
        if let encodedBytes, encodedBytes > ProfileLimits.encodedBytes { throw ProfileValidationError(.profileTooLarge) }
        guard profile.schema == "gesture-ime.profile.v1", profile.version >= 1 else { throw ProfileValidationError(.unsupportedSchema) }
        guard isValidID(profile.id), !profile.name.isEmpty, profile.name.unicodeScalars.count <= 128 else { throw ProfileValidationError(.unsupportedSchema) }
        guard profile.keyDefinitions.count <= ProfileLimits.keys else { throw ProfileValidationError(.limitKeys) }
        guard profile.layouts.count <= ProfileLimits.layouts else { throw ProfileValidationError(.limitLayouts) }
        guard profile.layers.count <= ProfileLimits.layers else { throw ProfileValidationError(.limitLayers) }
        guard profile.bindingSets.count <= ProfileLimits.bindingSets else { throw ProfileValidationError(.limitBindingSets) }
        guard profile.macros.count <= ProfileLimits.macros else { throw ProfileValidationError(.limitMacros) }
        for layout in profile.layouts where layout.placements.count > ProfileLimits.placementsPerLayout {
            throw ProfileValidationError(.limitPlacements, layout.id)
        }

        try validateUniqueIDs(profile.keyDefinitions.map(\.id))
        try validateUniqueIDs(profile.layouts.map(\.id))
        try validateUniqueIDs(profile.bindingSets.map(\.id))
        try validateUniqueIDs(profile.layers.map(\.id))
        try validateUniqueIDs(profile.macros.map(\.id))
        for id in profile.keyDefinitions.map(\.id) + profile.layouts.map(\.id) + profile.bindingSets.map(\.id) + profile.layers.map(\.id) + profile.macros.map(\.id) {
            guard isValidID(id) else { throw ProfileValidationError(.unsupportedSchema, id) }
        }

        for key in profile.keyDefinitions {
            try validatePresentation(key.presentation, owner: key.id)
            if let role = key.role, role.unicodeScalars.count > 64 {
                throw ProfileValidationError(.unsupportedSchema, key.id)
            }
        }
        for layout in profile.layouts {
            for placement in layout.placements {
                guard (0...255).contains(placement.row), (0...255).contains(placement.column) else {
                    throw ProfileValidationError(.unsupportedSchema, layout.id)
                }
                if let width = placement.width, (!width.isFinite || width <= 0 || width > 32) {
                    throw ProfileValidationError(.unsupportedSchema, layout.id)
                }
                if let height = placement.height, (!height.isFinite || height <= 0 || height > 32) {
                    throw ProfileValidationError(.unsupportedSchema, layout.id)
                }
            }
        }

        let p = profile.gesturePolicy
        guard p.deadZone.isFinite, p.stage1CommitDistance.isFinite, p.stage2CommitDistance.isFinite, p.angularHysteresisDegrees.isFinite,
              p.deadZone >= 0, p.deadZone <= 2,
              p.stage1CommitDistance > 0, p.stage1CommitDistance <= 4,
              p.stage2CommitDistance > 0, p.stage2CommitDistance <= 4,
              p.stage1CommitDistance >= p.deadZone, p.stage2CommitDistance >= p.deadZone,
              p.angularHysteresisDegrees >= 0, p.angularHysteresisDegrees < 45,
              p.maxDirectionalStages == 2 else {
            throw ProfileValidationError(.invalidGesturePolicy)
        }

        let keyIDs = Set(profile.keyDefinitions.map(\.id))
        let layoutIDs = Set(profile.layouts.map(\.id))
        let bindingSetIDs = Set(profile.bindingSets.map(\.id))
        let layerIDs = Set(profile.layers.map(\.id))
        let macroIDs = Set(profile.macros.map(\.id))

        for layout in profile.layouts {
            for placement in layout.placements where !keyIDs.contains(placement.keyID) {
                throw ProfileValidationError(.missingReference, placement.keyID)
            }
        }
        for layer in profile.layers {
            guard layoutIDs.contains(layer.layoutRef), bindingSetIDs.contains(layer.bindingSetRef) else {
                throw ProfileValidationError(.missingReference, layer.id)
            }
        }

        let totalBindings = profile.bindingSets.reduce(0) { $0 + $1.bindings.count }
        guard totalBindings <= ProfileLimits.bindingsTotal else { throw ProfileValidationError(.limitBindingsTotal) }

        var preflightTrieNodes = 0
        for set in profile.bindingSets {
            var seenByKey: [String: Set<GesturePath>] = [:]
            var prefixesByKey: [String: Set<GesturePath>] = [:]
            var countByKey: [String: Int] = [:]
            for binding in set.bindings {
                guard keyIDs.contains(binding.keyID) else { throw ProfileValidationError(.missingReference, binding.keyID) }
                guard binding.path.tokens.count <= ProfileLimits.pathDepth else { throw ProfileValidationError(.pathDepth) }
                countByKey[binding.keyID, default: 0] += 1
                if countByKey[binding.keyID, default: 0] > ProfileLimits.bindingsPerKey {
                    throw ProfileValidationError(.limitBindingsPerKey, binding.keyID)
                }
                if seenByKey[binding.keyID, default: []].contains(binding.path) {
                    throw ProfileValidationError(.duplicateBindingPath, "\(set.id):\(binding.keyID)")
                }
                seenByKey[binding.keyID, default: []].insert(binding.path)
                if !binding.path.tokens.isEmpty {
                    for i in 1...binding.path.tokens.count {
                        prefixesByKey[binding.keyID, default: []].insert(GesturePath(Array(binding.path.tokens.prefix(i))))
                    }
                }
                try validatePresentation(binding.behavior.presentation, owner: "\(set.id):\(binding.keyID)")
                let endpointCount = binding.behavior.onRelease.count + (binding.behavior.hold?.onStart.count ?? 0) + (binding.behavior.hold?.repeatBehavior?.actions.count ?? 0)
                guard endpointCount <= ProfileLimits.endpointActions else { throw ProfileValidationError(.limitActions) }
                try validateActions(binding.behavior.onRelease, inMacro: false, layerIDs: layerIDs, macroIDs: macroIDs)
                if let hold = binding.behavior.hold {
                    guard (50...5000).contains(hold.delayMs) else {
                        throw ProfileValidationError(.unsupportedSchema, "hold.delayMs")
                    }
                    try validateActions(hold.onStart, inMacro: false, layerIDs: layerIDs, macroIDs: macroIDs)
                    if let repeatBehavior = hold.repeatBehavior {
                        guard (16...5000).contains(repeatBehavior.intervalMs) else {
                            throw ProfileValidationError(.unsupportedSchema, "repeat.intervalMs")
                        }
                        try validateActions(repeatBehavior.actions, inMacro: false, layerIDs: layerIDs, macroIDs: macroIDs)
                    }
                }
            }
            preflightTrieNodes += seenByKey.count
            preflightTrieNodes += prefixesByKey.values.reduce(0) { $0 + $1.count }
        }
        guard preflightTrieNodes <= ProfileLimits.trieNodes else { throw ProfileValidationError(.limitTrieNodes) }

        for macro in profile.macros {
            guard macro.actions.count <= ProfileLimits.macroActions else { throw ProfileValidationError(.limitActions, macro.id) }
            try validateActions(macro.actions, inMacro: true, layerIDs: layerIDs, macroIDs: macroIDs)
        }
    }

    private static func validateUniqueIDs(_ values: [String]) throws {
        guard Set(values).count == values.count else { throw ProfileValidationError(.duplicateID) }
    }

    private static func validatePresentation(_ presentation: BindingPresentation?, owner: String) throws {
        guard let presentation else { return }
        if let text = presentation.text, text.unicodeScalars.count > 256 {
            throw ProfileValidationError(.unsupportedSchema, owner)
        }
        if let accessibilityLabel = presentation.accessibilityLabel, accessibilityLabel.unicodeScalars.count > 256 {
            throw ProfileValidationError(.unsupportedSchema, owner)
        }
    }

    private static func isValidID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard (1...128).contains(bytes.count), let first = bytes.first, isASCIIAlphaNumeric(first) else { return false }
        return bytes.dropFirst().allSatisfy { isASCIIAlphaNumeric($0) || $0 == 46 || $0 == 95 || $0 == 45 }
    }

    private static func isASCIIAlphaNumeric(_ c: UInt8) -> Bool {
        (48...57).contains(c) || (65...90).contains(c) || (97...122).contains(c)
    }

    private static func validateActions(_ actions: [ActionInvocation], inMacro: Bool, layerIDs: Set<String>, macroIDs: Set<String>) throws {
        for action in actions {
            guard commonActions.contains(action.actionID) else { throw ProfileValidationError(.unknownAction, action.actionID) }
            if inMacro && action.actionID == "macro.run" { throw ProfileValidationError(.macroNesting) }
            try validateArgumentSize(action)
            try validateActionShape(action, layerIDs: layerIDs, macroIDs: macroIDs)
        }
    }

    private static func validateArgumentSize(_ action: ActionInvocation) throws {
        let encoded = try JSONEncoder().encode(JSONValue.object(action.arguments))
        guard encoded.count <= ProfileLimits.argumentsBytes else { throw ProfileValidationError(.argumentTooLarge, action.actionID) }
        func scan(_ value: JSONValue) throws {
            switch value {
            case let .string(s):
                guard s.utf8.count <= ProfileLimits.stringArgumentBytes else { throw ProfileValidationError(.argumentTooLarge, action.actionID) }
            case let .object(o): try o.values.forEach(scan)
            case let .array(a): try a.forEach(scan)
            default: break
            }
        }
        try action.arguments.values.forEach(scan)
    }

    private static func validateActionShape(_ action: ActionInvocation, layerIDs: Set<String>, macroIDs: Set<String>) throws {
        let a = action.arguments
        func exact(_ keys: Set<String>) throws {
            guard Set(a.keys) == keys else { throw ProfileValidationError(.invalidActionArguments, action.actionID) }
        }
        func string(_ key: String) throws -> String {
            guard let v = a[key]?.stringValue else { throw ProfileValidationError(.invalidActionArguments, action.actionID) }
            return v
        }
        switch action.actionID {
        case "noop", "layer.pop", "conversion.commit", "system.nextKeyboard", "system.dismissKeyboard":
            try exact([])
        case "text.insert", "text.directInsert":
            try exact(["text"]); _ = try string("text")
        case "edit.delete":
            try exact(["count"]); guard let v = a["count"]?.intValue, v != 0, (-64...64).contains(v) else { throw ProfileValidationError(.invalidActionArguments, action.actionID) }
        case "cursor.move":
            try exact(["offset"]); guard let v = a["offset"]?.intValue, v != 0, (-64...64).contains(v) else { throw ProfileValidationError(.invalidActionArguments, action.actionID) }
        case "layer.set", "layer.push":
            try exact(["layer"]); let ref = try string("layer"); guard layerIDs.contains(ref) else { throw ProfileValidationError(.missingReference, ref) }
        case "profile.switch":
            try exact(["profile"]); _ = try string("profile")
        case "conversion.selectCandidate":
            try exact(["index"]); guard let v = a["index"]?.intValue, v >= 0 else { throw ProfileValidationError(.invalidActionArguments, action.actionID) }
        case "panel.open":
            try exact(["panel"]); _ = try string("panel")
        case "macro.run":
            try exact(["macro"]); let ref = try string("macro"); guard macroIDs.contains(ref) else { throw ProfileValidationError(.missingReference, ref) }
        default:
            throw ProfileValidationError(.unknownAction, action.actionID)
        }
    }
}
