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
