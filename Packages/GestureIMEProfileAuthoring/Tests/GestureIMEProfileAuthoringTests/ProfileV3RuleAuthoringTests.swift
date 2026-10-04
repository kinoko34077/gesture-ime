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
    #expect(rules.branches.allSatisfy(\.isAdvanced))
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
    let board = try document.v3BoardSummaries().first!.id
    let entry = try document.v3BoardEntries(boardID: board).first!.id
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
    var object = original.objectValue!
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

    let multi = try json(#"{"onRelease":[{"actionID":"a","arguments":{}},{"actionID":"b","arguments":{}}]}"#)
    var locked = ProfileV3BranchBehavior(multi)
    #expect(!locked.actionsEditable)
    locked.displayText = "x"
    #expect(locked.applied(to: multi).objectValue?["onRelease"] == multi.objectValue?["onRelease"])
}
