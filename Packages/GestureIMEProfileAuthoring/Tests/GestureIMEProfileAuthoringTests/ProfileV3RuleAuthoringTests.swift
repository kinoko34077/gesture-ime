import Foundation
import Testing
@testable import GestureIMEProfileAuthoring

// #102 / #95 §F4 — IF/ELSE vocabulary round-trips; anything else is preserved.

private func json(_ text: String) throws -> JSONNode {
    try JSONNode(foundation: JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]))
}

private let behaviorA = #"{"onRelease":[{"type":"text.insert","text":"a"}]}"#
private let behaviorB = #"{"onRelease":[{"type":"text.insert","text":"b"}]}"#

@Test
func vocabularyBranchesRoundTripExactly() throws {
    let resolver = try json("""
    {"cases":[
      {"when":{"fact":"conversion.active"},"behavior":\(behaviorA)},
      {"when":{"not":{"fact":"composition.empty"}},"behavior":\(behaviorA)},
      {"when":{"eq":[{"fact":"host.returnKey"},{"literal":"search"}]},"behavior":\(behaviorA)},
      {"when":{"all":[{"fact":"conversion.hasCandidates"},{"eq":[{"state":"s.mode"},{"literal":true}]}]},"behavior":\(behaviorA),"note":"x"},
      {"when":{"any":[{"transformMatch":{"tableRef":"kana.small","target":"compositionTail"}},{"eq":[{"fact":"layer.id"},{"literal":"layer.en"}]}]},"behavior":\(behaviorA)}
    ],"default":\(behaviorB),"future":1}
    """)
    let rules = try ProfileV3Rules.parse(resolver)
    #expect(rules.branches.allSatisfy { !$0.isAdvanced })
    #expect(rules.extra["future"] == .integer(1))
    guard case .editable(let condition, _, let extra) = rules.branches[3] else {
        Issue.record("expected editable"); return
    }
    #expect(condition.combine == .all)
    #expect(condition.terms[1].test == .stateEquals(stateID: "s.mode", value: .bool(true)))
    #expect(extra["note"] == .string("x"))
    #expect(try ProfileV3Rules.encode(rules) == resolver)
}

@Test
func unsupportedConditionsStayAdvancedAndUnchanged() throws {
    let resolver = try json("""
    {"cases":[
      {"when":{"in":[{"fact":"host.keyboardType"},["email","url"]]},"behavior":\(behaviorA)},
      {"when":{"all":[{"any":[{"fact":"conversion.active"}]}]},"behavior":\(behaviorA)},
      {"when":{"not":{"not":{"fact":"conversion.active"}}},"behavior":\(behaviorA)},
      {"when":{"eq":[{"literal":"search"},{"fact":"host.returnKey"}]},"behavior":\(behaviorA)},
      {"when":{"fact":"host.needsInputModeSwitchKey"},"behavior":\(behaviorA)}
    ],"default":\(behaviorB)}
    """)
    var rules = try ProfileV3Rules.parse(resolver)
    #expect(rules.branches.allSatisfy { $0.isAdvanced })
    #expect(try ProfileV3Rules.encode(rules) == resolver)

    // Adding an editable IF in front keeps every advanced branch byte-identical.
    rules.branches.insert(.editable(
        condition: ProfileV3RuleCondition(terms: [ProfileV3RuleTerm(.flag(.conversionActive))]),
        behavior: try json(behaviorA),
        extra: [:]
    ), at: 0)
    let cases = try ProfileV3Rules.encode(rules).objectValue?["cases"]?.arrayValue ?? []
    #expect(Array(cases.dropFirst()) == resolver.objectValue?["cases"]?.arrayValue)
}

@Test
func elseIsRequiredAndEmptyConditionsAreRejected() throws {
    #expect(throws: ProfileAuthoringError.self) {
        try ProfileV3Rules.parse(json(#"{"cases":[]}"#))
    }
    let rules = ProfileV3RuleSet(
        branches: [.editable(condition: ProfileV3RuleCondition(combine: .all, terms: []), behavior: try json(behaviorA), extra: [:])],
        elseBehavior: try json(behaviorB)
    )
    #expect(throws: ProfileAuthoringError.self) { try ProfileV3Rules.encode(rules) }
}

@Test
func simpleTextBehaviorRoundTrips() throws {
    let behavior = ProfileV3Rules.textBehavior("ゃ")
    #expect(ProfileV3Rules.simpleText(of: behavior) == "ゃ")
    #expect(ProfileV3Rules.simpleText(of: try json(#"{"onRelease":[]}"#)) == nil)

    var document = try ProfileDocument.emptyV3(id: "user.v3.rules", name: "Rules")
    try document.v3CreateLayer(fromPreset: .numeric, layerID: "layer.num", name: nil)
    let layer = try document.v3LayerSummaries().first { $0.id == "layer.num" }
    let board = try #require(layer?.rootBoardID)
    let entry = try #require(try document.v3BoardEntries(boardID: board).first?.id)
    var rules = try document.v3EntryRules(boardID: board, entryID: entry)
    rules.branches.append(.editable(
        condition: ProfileV3RuleCondition(terms: [ProfileV3RuleTerm(.flag(.conversionActive), negated: true)]),
        behavior: ProfileV3Rules.textBehavior("x"),
        extra: [:]
    ))
    try document.v3SetEntryRules(boardID: board, entryID: entry, rules: rules)
    #expect(try document.v3EntryRules(boardID: board, entryID: entry) == rules)
}

@Test
func closedCatalogLiteralsOutsideTheListAreAdvanced() throws {
    let resolver = try json("""
    {"cases":[{"when":{"eq":[{"fact":"host.returnKey"},{"literal":"launch"}]},"behavior":\(behaviorA)}],"default":\(behaviorB)}
    """)
    #expect(try ProfileV3Rules.parse(resolver).branches[0].isAdvanced)
}

@Test
func branchBehaviorEditsKeepUnknownMembers() throws {
    let original = ProfileV3Rules.textBehavior("か")
    var object = try #require(original.objectValue)
    object["hold"] = .object(["x": .integer(1)])
    let behavior = JSONNode.object(object)

    var edit = ProfileV3BranchBehavior(behavior)
    #expect(edit.displayText == "か")
    #expect(edit.action?.actionID == "text.insert")
    #expect(edit.applied(to: behavior) == behavior)

    edit.displayText = "が"
    edit.action = ProfileActionDraft(actionID: "edit.delete", arguments: ["count": .integer(1)])
    edit.transition = ProfileV3TransitionDraft(targetBoardID: "board.next")
    let updated = edit.applied(to: behavior)
    #expect(updated.objectValue?["hold"] == .object(["x": .integer(1)]))
    #expect(ProfileV3BranchBehavior(updated) == edit)

    let multi = try json(#"{"onRelease":[{"actionID":"a","arguments":{},"future":1},{"actionID":"b","arguments":{"x":"y"}}]}"#)
    var stacked = ProfileV3BranchBehavior(multi)
    #expect(stacked.actionsEditable)
    #expect(stacked.actions.count == 2)
    #expect(stacked.actions[0].extra["future"] == .integer(1))
    #expect(stacked.applied(to: multi) == multi)

    stacked.actions.swapAt(0, 1)
    let reordered = stacked.applied(to: multi)
    #expect(ProfileV3BranchBehavior(reordered).actions.map(\.actionID) == ["b", "a"])

    let malformed = try json(#"{"onRelease":[{"arguments":{}}]}"#)
    var locked = ProfileV3BranchBehavior(malformed)
    #expect(!locked.actionsEditable)
    locked.displayText = "x"
    #expect(locked.applied(to: malformed).objectValue?["onRelease"] == malformed.objectValue?["onRelease"])
}


@Test
func ordinaryMutationCannotMoveOrDeleteAdvancedBranches() throws {
    let advancedNode = try json(#"{"when":{"fact":"host.needsInputModeSwitchKey"},"behavior":{"onRelease":[]}}"#)
    let editableA = ProfileV3RuleBranch.editable(
        condition: ProfileV3RuleCondition(terms: [ProfileV3RuleTerm(.flag(.conversionActive))]),
        behavior: try json(behaviorA),
        extra: [:]
    )
    let editableB = ProfileV3RuleBranch.editable(
        condition: ProfileV3RuleCondition(terms: [ProfileV3RuleTerm(.flag(.compositionEmpty))]),
        behavior: try json(behaviorB),
        extra: [:]
    )
    var rules = ProfileV3RuleSet(
        branches: [editableA, .advanced(advancedNode), editableB],
        elseBehavior: try json(behaviorB)
    )

    #expect(!rules.canMoveOrdinaryBranch(from: 0, to: 2))
    let blockedMove = rules.moveOrdinaryBranch(from: 0, to: 2)
    let blockedDelete = rules.deleteOrdinaryBranch(at: 1)
    #expect(!blockedMove)
    #expect(!blockedDelete)
    #expect(rules.branches[1] == .advanced(advancedNode))

    rules.branches.insert(editableB, at: 1)
    #expect(rules.canMoveOrdinaryBranch(from: 0, to: 1))
    let allowedMove = rules.moveOrdinaryBranch(from: 0, to: 1)
    #expect(allowedMove)
    #expect(rules.branches[2] == .advanced(advancedNode))
    let allowedDelete = rules.deleteOrdinaryBranch(at: 0)
    #expect(allowedDelete)
    #expect(rules.branches.contains(.advanced(advancedNode)))
}

@Test
func unsupportedSingleActionsRemainUntouchedWhenOtherBehaviorFieldsChange() throws {
    let payloads: [JSONNode] = [
        try json(#"{"actionID":"text.transform","arguments":{"table":"kana.small"},"future":"x"}"#),
        try json(#"{"actionID":"state.set","arguments":{"state":"s.mode","value":true}}"#),
        try json(#"{"actionID":"extension.future","arguments":{"x":1},"opaque":{"y":2}}"#)
    ]

    for payload in payloads {
        let original = JSONNode.object([
            "onRelease": .array([payload]),
            "presentation": .object([
                "text": .object(["base": .string("A"), "transforms": .array([])])
            ])
        ])
        var edit = ProfileV3BranchBehavior(original)
        edit.displayText = "B"
        let updated = edit.applied(to: original)
        #expect(updated.objectValue?["onRelease"] == .array([payload]))
    }
}

@Test
func ordinaryTextActionDraftingUsesResolvedStringAndPreservesTransforms() throws {
    let transform = try json(#"{"when":{"fact":"conversion.active"},"tableRef":"kana.small"}"#)
    let previous = ProfileActionDraft(
        actionID: "text.insert",
        arguments: [
            "text": .object([
                "base": .string("a"),
                "transforms": .array([transform]),
                "future": .integer(7)
            ])
        ],
        extra: ["note": .string("keep")]
    )

    #expect(ProfileV3RuleActionDrafting.argumentText(
        from: previous,
        key: "text",
        resolvedString: true
    ) == "a")

    let edited = ProfileV3RuleActionDrafting.makeDraft(
        actionID: "text.insert",
        argumentKey: "text",
        argumentText: "b",
        resolvedStringArgument: true,
        preserving: previous
    )
    let text = try #require(edited.arguments["text"]?.objectValue)
    #expect(text["base"] == .string("b"))
    #expect(text["transforms"] == .array([transform]))
    #expect(text["future"] == .integer(7))
    #expect(edited.extra["note"] == .string("keep"))

    let direct = ProfileV3RuleActionDrafting.makeDraft(
        actionID: "text.directInsert",
        argumentKey: "text",
        argumentText: "x",
        resolvedStringArgument: true
    )
    #expect(direct.arguments["text"] == .object([
        "base": .string("x"),
        "transforms": .array([])
    ]))
}
