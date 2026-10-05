import Foundation

// #102 / #95 §F4 — IF/ELSE authoring over an EntryResolver. The resolver's
// `cases` (first match wins) are IF branches; `default` is ELSE and is never
// deletable. Only the frozen §F4 vocabulary is editable; any other `when`
// is an advanced branch that is shown read-only and written back unchanged.

public enum ProfileV3RuleFlag: String, CaseIterable, Sendable {
    case conversionActive = "conversion.active"          // 変換中
    case conversionHasCandidates = "conversion.hasCandidates"  // 変換候補がある
    case compositionEmpty = "composition.empty"          // 入力中の文字がない
    case autocapitalizeNext = "host.autocapitalizeNext"  // 自動で大文字にする位置
}

public enum ProfileV3RuleStringFact: String, CaseIterable, Sendable {
    case returnKey = "host.returnKey"        // Return用途
    case keyboardType = "host.keyboardType"  // 入力欄の種類
    case layerID = "layer.id"                // キーボード面

    /// Closed literal catalogs (mirrors the runtime's `HostInputFactsV3`).
    /// `nil` = the catalog is the document's Layer IDs.
    public var catalog: [String]? {
        switch self {
        case .returnKey:
            ["default", "go", "search", "send", "next", "done", "join", "route", "continue", "emergencyCall"]
        case .keyboardType:
            ["default", "ascii", "numbers", "url", "email", "phone", "decimal", "twitter", "webSearch"]
        case .layerID:
            nil
        }
    }
}

public enum ProfileV3RuleTest: Equatable, Sendable {
    case flag(ProfileV3RuleFlag)
    case factEquals(ProfileV3RuleStringFact, String)
    /// `state` equals a string or boolean literal.
    case stateEquals(stateID: String, value: JSONNode)
    /// 直前の文字が変換表に含まれる
    case transformMatch(tableID: String)
}

public struct ProfileV3RuleTerm: Equatable, Sendable {
    public var negated: Bool
    public var test: ProfileV3RuleTest

    public init(_ test: ProfileV3RuleTest, negated: Bool = false) {
        self.test = test
        self.negated = negated
    }
}

public struct ProfileV3RuleCondition: Equatable, Sendable {
    public enum Combine: Equatable, Sendable { case single, all, any }

    public var combine: Combine
    public var terms: [ProfileV3RuleTerm]

    public init(combine: Combine = .single, terms: [ProfileV3RuleTerm]) {
        self.combine = combine
        self.terms = terms
    }
}

public enum ProfileV3RuleBranch: Equatable, Sendable {
    /// `extra` keeps unknown case members (besides `when`/`behavior`).
    case editable(condition: ProfileV3RuleCondition, behavior: JSONNode, extra: [String: JSONNode])
    /// Outside the §F4 vocabulary: the whole case object, preserved as-is.
    case advanced(JSONNode)

    public var isAdvanced: Bool {
        if case .advanced = self { return true }
        return false
    }
}

public struct ProfileV3RuleSet: Equatable, Sendable {
    public var branches: [ProfileV3RuleBranch]
    /// ELSE. Always present.
    public var elseBehavior: JSONNode
    /// Unknown resolver members (besides `cases`/`default`).
    public var extra: [String: JSONNode]

    public init(branches: [ProfileV3RuleBranch], elseBehavior: JSONNode, extra: [String: JSONNode] = [:]) {
        self.branches = branches
        self.elseBehavior = elseBehavior
        self.extra = extra
    }
}

extension ProfileV3RuleSet {
    /// Ordinary authoring must treat advanced branches as semantic barriers.
    /// Editable branches may be reordered only within one contiguous editable
    /// segment, so an advanced branch never moves relative to ordinary rules.
    public func canMoveOrdinaryBranch(from source: Int, to destination: Int) -> Bool {
        guard branches.indices.contains(source),
              branches.indices.contains(destination),
              source != destination,
              !branches[source].isAdvanced,
              !branches[destination].isAdvanced else {
            return false
        }
        let lower = min(source, destination)
        let upper = max(source, destination)
        return !branches[lower...upper].contains(where: \.isAdvanced)
    }

    @discardableResult
    public mutating func moveOrdinaryBranch(from source: Int, to destination: Int) -> Bool {
        guard canMoveOrdinaryBranch(from: source, to: destination) else { return false }
        let branch = branches.remove(at: source)
        branches.insert(branch, at: destination)
        return true
    }

    @discardableResult
    public mutating func deleteOrdinaryBranch(at index: Int) -> Bool {
        guard branches.indices.contains(index), !branches[index].isAdvanced else { return false }
        branches.remove(at: index)
        return true
    }
}

public enum ProfileV3Rules {
    public static func parse(_ resolver: JSONNode) throws -> ProfileV3RuleSet {
        guard var object = resolver.objectValue,
              let cases = object.removeValue(forKey: "cases")?.arrayValue,
              let fallback = object.removeValue(forKey: "default") else {
            throw ProfileAuthoringError.invalidJSON("resolverの形式が不正です")
        }
        let branches = cases.map { node -> ProfileV3RuleBranch in
            guard var item = node.objectValue,
                  let when = item.removeValue(forKey: "when"),
                  let behavior = item.removeValue(forKey: "behavior"),
                  let condition = condition(when),
                  encode(condition) == when else {
                return .advanced(node)
            }
            return .editable(condition: condition, behavior: behavior, extra: item)
        }
        return ProfileV3RuleSet(branches: branches, elseBehavior: fallback, extra: object)
    }

    public static func encode(_ rules: ProfileV3RuleSet) throws -> JSONNode {
        var object = rules.extra
        object["cases"] = .array(try rules.branches.map { branch in
            switch branch {
            case .advanced(let node):
                return node
            case .editable(let condition, let behavior, let extra):
                guard !condition.terms.isEmpty,
                      condition.combine != .single || condition.terms.count == 1 else {
                    throw ProfileAuthoringError.invalidJSON("条件が空です")
                }
                var item = extra
                item["when"] = encode(condition)
                item["behavior"] = behavior
                return .object(item)
            }
        })
        object["default"] = rules.elseBehavior
        return .object(object)
    }

    public static func encode(_ condition: ProfileV3RuleCondition) -> JSONNode {
        let terms = condition.terms.map(encode)
        switch condition.combine {
        case .single: return terms.first ?? .object(["all": .array([])])
        case .all: return .object(["all": .array(terms)])
        case .any: return .object(["any": .array(terms)])
        }
    }

    static func encode(_ term: ProfileV3RuleTerm) -> JSONNode {
        let node: JSONNode
        switch term.test {
        case .flag(let flag):
            node = .object(["fact": .string(flag.rawValue)])
        case .factEquals(let fact, let value):
            node = .object(["eq": .array([
                .object(["fact": .string(fact.rawValue)]),
                .object(["literal": .string(value)])
            ])])
        case .stateEquals(let stateID, let value):
            node = .object(["eq": .array([
                .object(["state": .string(stateID)]),
                .object(["literal": value])
            ])])
        case .transformMatch(let tableID):
            node = .object(["transformMatch": .object([
                "tableRef": .string(tableID),
                "target": .string("compositionTail")
            ])])
        }
        return term.negated ? .object(["not": node]) : node
    }

    static func condition(_ node: JSONNode) -> ProfileV3RuleCondition? {
        if let object = node.objectValue, object.count == 1 {
            if let list = object["all"]?.arrayValue ?? object["any"]?.arrayValue {
                let terms = list.compactMap(term)
                guard !list.isEmpty, terms.count == list.count else { return nil }
                return ProfileV3RuleCondition(combine: object["all"] != nil ? .all : .any, terms: terms)
            }
        }
        return term(node).map { ProfileV3RuleCondition(terms: [$0]) }
    }

    static func term(_ node: JSONNode) -> ProfileV3RuleTerm? {
        if let inner = node.objectValue?["not"], node.objectValue?.count == 1 {
            return test(inner).map { ProfileV3RuleTerm($0, negated: true) }
        }
        return test(node).map { ProfileV3RuleTerm($0) }
    }

    static func test(_ node: JSONNode) -> ProfileV3RuleTest? {
        guard let object = node.objectValue, object.count == 1,
              let member = object.first else { return nil }
        let value = member.value
        switch member.key {
        case "fact":
            return value.stringValue.flatMap(ProfileV3RuleFlag.init(rawValue:)).map(ProfileV3RuleTest.flag)
        case "transformMatch":
            guard let match = value.objectValue, match.count == 2,
                  match["target"]?.stringValue == "compositionTail",
                  let table = match["tableRef"]?.stringValue else { return nil }
            return .transformMatch(tableID: table)
        case "eq":
            guard let pair = value.arrayValue, pair.count == 2,
                  let left = pair[0].objectValue, left.count == 1,
                  let right = pair[1].objectValue, right.count == 1,
                  let literal = right["literal"] else { return nil }
            if let fact = left["fact"]?.stringValue.flatMap(ProfileV3RuleStringFact.init(rawValue:)),
               let text = literal.stringValue,
               fact.catalog?.contains(text) ?? true {
                return .factEquals(fact, text)
            }
            if let state = left["state"]?.stringValue {
                switch literal {
                case .string, .bool: return .stateEquals(stateID: state, value: literal)
                default: return nil
                }
            }
            return nil
        default:
            return nil
        }
    }
}

extension ProfileDocument {
    public func v3EntryRules(boardID: String, entryID: String) throws -> ProfileV3RuleSet {
        try ProfileV3Rules.parse(v3EntryResolver(boardID: boardID, entryID: entryID))
    }

    public mutating func v3SetEntryRules(boardID: String, entryID: String, rules: ProfileV3RuleSet) throws {
        try v3SetEntryResolver(boardID: boardID, entryID: entryID, resolver: ProfileV3Rules.encode(rules))
    }
}

extension ProfileV3Rules {
    /// The inserted text when `behavior` is exactly "show and insert one text".
    public static func simpleText(of behavior: JSONNode) -> String? {
        guard let actions = behavior.objectValue?["onRelease"]?.arrayValue, actions.count == 1,
              let text = actions[0].objectValue?["arguments"]?.objectValue?["text"]?
                .objectValue?["base"]?.stringValue,
              textBehavior(text) == behavior else { return nil }
        return text
    }

    /// A behavior that shows and inserts `text` (same shape as presets).
    public static func textBehavior(_ text: String) -> JSONNode {
        ProfileDocument.v3TextResolver(text).objectValue?["default"] ?? .null
    }
}

/// Shared drafting rules for the ordinary IF/ELSE Action editor.
/// In particular, v3 text actions use a ResolvedString object rather than a
/// raw string; existing conditional transforms/extra members are preserved.
public enum ProfileV3RuleActionDrafting {
    public static func argumentText(
        from action: ProfileActionDraft,
        key: String,
        resolvedString: Bool = false
    ) -> String? {
        guard let value = action.arguments[key] else { return nil }
        if resolvedString {
            return value.objectValue?["base"]?.stringValue
        }
        switch value {
        case .string(let text): return text
        case .integer(let number): return String(number)
        default: return nil
        }
    }

    public static func makeDraft(
        actionID: String,
        argumentKey: String?,
        argumentText: String,
        integerArgument: Bool = false,
        defaultInteger: Int64 = 0,
        resolvedStringArgument: Bool = false,
        preserving previous: ProfileActionDraft? = nil
    ) -> ProfileActionDraft {
        let sameAction = previous?.actionID == actionID ? previous : nil
        var arguments: [String: JSONNode] = [:]

        if let argumentKey {
            if resolvedStringArgument {
                var resolved = sameAction?.arguments[argumentKey]?.objectValue
                    ?? ["transforms": .array([])]
                if resolved["transforms"] == nil {
                    resolved["transforms"] = .array([])
                }
                resolved["base"] = .string(argumentText)
                arguments[argumentKey] = .object(resolved)
            } else if integerArgument {
                arguments[argumentKey] = .integer(Int64(argumentText) ?? defaultInteger)
            } else {
                arguments[argumentKey] = .string(argumentText)
            }
        }

        return ProfileActionDraft(
            actionID: actionID,
            arguments: arguments,
            extra: sameAction?.extra ?? [:]
        )
    }
}

/// #95 §F4 branch behavior editor: 表示 / ordered 動作 stack / 次の段階.
/// Unknown behavior members and malformed Action nodes remain untouched.
public struct ProfileV3BranchBehavior: Equatable, Sendable {
    public var displayText: String?
    /// Ordered onRelease action stack for ordinary authoring.
    public var actions: [ProfileActionDraft]
    /// False only when an onRelease item cannot be represented losslessly as
    /// an Action draft. In that case the original JSON remains untouched.
    public let actionsEditable: Bool
    public var transition: ProfileV3TransitionDraft?

    /// Compatibility convenience for callers that still work with zero/one
    /// Action. Multi-Action behavior intentionally returns nil here.
    public var action: ProfileActionDraft? {
        get { actions.count == 1 ? actions[0] : nil }
        set { actions = newValue.map { [$0] } ?? [] }
    }

    public init(_ behavior: JSONNode) {
        let object = behavior.objectValue ?? [:]
        displayText = object["presentation"]?.objectValue?["text"]?.objectValue?["base"]?.stringValue

        let rawActions = object["onRelease"]?.arrayValue ?? []
        let parsedActions = rawActions.compactMap { node -> ProfileActionDraft? in
            guard var item = node.objectValue,
                  let id = item["actionID"]?.stringValue else {
                return nil
            }
            item.removeValue(forKey: "actionID")
            let arguments = item.removeValue(forKey: "arguments")?.objectValue ?? [:]
            return ProfileActionDraft(
                actionID: id,
                arguments: arguments,
                extra: item
            )
        }
        actionsEditable = parsedActions.count == rawActions.count
        actions = parsedActions

        transition = object["transition"]?.objectValue.flatMap { item in
            guard let target = item["targetBoardRef"]?.stringValue,
                  let lifetime = item["lifetime"]?.stringValue.flatMap(ProfileV3TransitionLifetime.init(rawValue:))
            else { return nil }
            return ProfileV3TransitionDraft(targetBoardID: target, lifetime: lifetime)
        }
    }

    public func applied(to behavior: JSONNode) -> JSONNode {
        var object = behavior.objectValue ?? [:]
        var presentation = object["presentation"]?.objectValue ?? [:]
        if let displayText, !displayText.isEmpty {
            var text = presentation["text"]?.objectValue ?? ["transforms": .array([])]
            text["base"] = .string(displayText)
            presentation["text"] = .object(text)
        } else {
            presentation.removeValue(forKey: "text")
        }
        if presentation.isEmpty {
            object.removeValue(forKey: "presentation")
        } else {
            object["presentation"] = .object(presentation)
        }

        if actionsEditable {
            if actions.isEmpty {
                object.removeValue(forKey: "onRelease")
            } else {
                object["onRelease"] = .array(actions.map { action in
                    var node = action.extra
                    node["actionID"] = .string(action.actionID)
                    node["arguments"] = .object(action.arguments)
                    return .object(node)
                })
            }
        }

        if let transition {
            var node = object["transition"]?.objectValue ?? [:]
            node["targetBoardRef"] = .string(transition.targetBoardID)
            node["lifetime"] = .string(transition.lifetime.rawValue)
            object["transition"] = .object(node)
        } else {
            object.removeValue(forKey: "transition")
        }
        return .object(object)
    }
}
