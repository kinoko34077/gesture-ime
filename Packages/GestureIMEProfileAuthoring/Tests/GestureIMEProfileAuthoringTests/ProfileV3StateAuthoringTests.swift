import Testing
@testable import GestureIMEProfileAuthoring

@Test
func stateIDsAreGeneratedInternallyWithoutRewritingExistingIdentity() {
    #expect(ProfileV3StateAuthoringPolicy.nextStateID(existingIDs: []) == "state.state-1")
    #expect(
        ProfileV3StateAuthoringPolicy.nextStateID(
            existingIDs: ["latinCase", "state.state-1", "state.state-3"]
        ) == "state.state-2"
    )
}

@Test
func enumPolicyMatchesExistingStateConstraints() {
    #expect(
        ProfileV3StateAuthoringPolicy.isValidEnum(
            values: ["lower", "upper"],
            defaultValue: "lower"
        )
    )
    #expect(
        !ProfileV3StateAuthoringPolicy.isValidEnum(
            values: ["same", "same"],
            defaultValue: "same"
        )
    )
    #expect(
        !ProfileV3StateAuthoringPolicy.isValidEnum(
            values: ["lower", "upper"],
            defaultValue: "missing"
        )
    )
}

@Test
func enumDraftValidationRejectsEmptyValuesAndMoveIsBounded() {
    #expect(
        ProfileV3StateAuthoringPolicy.enumValidationError(
            values: [""],
            defaultValue: ""
        ) != nil
    )
    #expect(
        ProfileV3StateAuthoringPolicy.movedValues(
            ["a", "b", "c"],
            from: 1,
            by: -1
        ) == ["b", "a", "c"]
    )
    #expect(
        ProfileV3StateAuthoringPolicy.movedValues(
            ["a", "b"],
            from: 0,
            by: -1
        ) == nil
    )
}

@Test
func deletingCurrentEnumDefaultRequiresExplicitReplacement() throws {
    let blocked = ProfileV3StateAuthoringPolicy.deletingEnumValue(
        at: 0,
        values: ["lower", "upper", "caps"],
        defaultValue: "lower",
        replacementDefault: nil
    )
    #expect(blocked == nil)

    let accepted = try #require(
        ProfileV3StateAuthoringPolicy.deletingEnumValue(
            at: 0,
            values: ["lower", "upper", "caps"],
            defaultValue: "lower",
            replacementDefault: "upper"
        )
    )
    #expect(accepted.values == ["upper", "caps"])
    #expect(accepted.defaultValue == "upper")
}

@Test
func deletingNonDefaultPreservesCurrentDefaultAndLastValueCannotDisappear() throws {
    let accepted = try #require(
        ProfileV3StateAuthoringPolicy.deletingEnumValue(
            at: 1,
            values: ["lower", "upper"],
            defaultValue: "lower",
            replacementDefault: nil
        )
    )
    #expect(accepted.values == ["lower"])
    #expect(accepted.defaultValue == "lower")

    #expect(
        ProfileV3StateAuthoringPolicy.deletingEnumValue(
            at: 0,
            values: ["only"],
            defaultValue: "only",
            replacementDefault: nil
        ) == nil
    )
}


@Test
func duplicatingStatePreservesUnknownMembersButGetsNewIdentity() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.state-duplicate",
        name: "State Duplicate"
    )
    try document.v3SetSemanticSectionNode(
        .states,
        node: .array([
            .object([
                "id": .string("latinCase"),
                "type": .string("enum"),
                "values": .array([.string("lower"), .string("upper")]),
                "default": .string("lower"),
                "futureStateMember": .object(["keep": .bool(true)])
            ])
        ])
    )

    let newID = try document.v3NewStateID()
    #expect(newID == "state.state-1")
    try document.v3DuplicateState(sourceID: "latinCase", newID: newID)

    let node = try document.v3SemanticSectionNode(.states)
    let states = try #require(node.arrayValue)
    #expect(states.count == 2)

    let duplicate = try #require(
        states.first(where: { $0.objectValue?["id"]?.stringValue == newID })?
            .objectValue
    )
    #expect(duplicate["type"] == .string("enum"))
    #expect(duplicate["default"] == .string("lower"))
    #expect(
        duplicate["futureStateMember"] ==
            .object(["keep": .bool(true)])
    )
}


@Test
func generatedStateIDAlsoAvoidsUnsupportedAdvancedNodes() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.advanced-state-id",
        name: "Advanced State ID"
    )
    try document.v3SetSemanticSectionNode(
        .states,
        node: .array([
            .object([
                "id": .string("state.state-1"),
                "type": .string("future-state-kind"),
                "default": .string("opaque"),
                "future": .bool(true)
            ])
        ])
    )

    #expect(try document.v3NewStateID() == "state.state-2")
}
