import Testing
@testable import GestureIMEProfileAuthoring

@Test
func stateIDsAreGeneratedInternallyWithoutRenamingExistingIdentity() {
    #expect(
        ProfileV3StateAuthoringPolicy.nextStateID(
            existingIDs: []
        ) == "state.new"
    )
    #expect(
        ProfileV3StateAuthoringPolicy.nextStateID(
            existingIDs: ["state.new", "state.new.2"]
        ) == "state.new.3"
    )
}

@Test
func generatedStateIDAvoidsUnsupportedAdvancedNodes() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.advanced-state-id",
        name: "Advanced State ID"
    )
    try document.v3SetSemanticSectionNode(
        .states,
        node: .array([
            .object([
                "id": .string("state.new"),
                "type": .string("future-state-kind"),
                "default": .string("opaque"),
                "future": .bool(true)
            ])
        ])
    )

    #expect(try document.v3NewStateID() == "state.new.2")
}

@Test
func enumDraftValidationPreservesSchemaMeaning() {
    #expect(
        ProfileV3StateAuthoringPolicy.enumValidationError(
            values: ["lower", "upper"],
            defaultValue: "lower"
        ) == nil
    )
    #expect(
        ProfileV3StateAuthoringPolicy.enumValidationError(
            values: [],
            defaultValue: ""
        ) != nil
    )
    #expect(
        ProfileV3StateAuthoringPolicy.enumValidationError(
            values: [""],
            defaultValue: ""
        ) != nil
    )
    #expect(
        ProfileV3StateAuthoringPolicy.enumValidationError(
            values: ["a", "a"],
            defaultValue: "a"
        ) != nil
    )
    #expect(
        ProfileV3StateAuthoringPolicy.enumValidationError(
            values: ["a", "b"],
            defaultValue: "missing"
        ) != nil
    )
}

@Test
func enumDraftMoveIsBoundedAndStable() {
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
func deletingCurrentDefaultRequiresExplicitReplacement() {
    #expect(
        ProfileV3StateAuthoringPolicy.deletingValue(
            at: 0,
            from: ["a", "b"],
            defaultValue: "a",
            replacementDefault: nil
        ) == nil
    )

    let result = ProfileV3StateAuthoringPolicy.deletingValue(
        at: 0,
        from: ["a", "b"],
        defaultValue: "a",
        replacementDefault: "b"
    )
    #expect(result?.values == ["b"])
    #expect(result?.defaultValue == "b")
}

@Test
func deletingNonDefaultKeepsDefaultAndLastValueCannotDisappear() {
    let result = ProfileV3StateAuthoringPolicy.deletingValue(
        at: 1,
        from: ["a", "b", "c"],
        defaultValue: "a",
        replacementDefault: nil
    )
    #expect(result?.values == ["a", "c"])
    #expect(result?.defaultValue == "a")

    #expect(
        ProfileV3StateAuthoringPolicy.deletingValue(
            at: 0,
            from: ["only"],
            defaultValue: "only",
            replacementDefault: nil
        ) == nil
    )
}
