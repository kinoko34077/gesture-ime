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

import Testing
@testable import GestureIMEProfileAuthoring

@Test
func enumDraftValidationPreservesSchemaMeaning() {
    #expect(ProfileV3StateAuthoringPolicy.enumValidationError(
        values: ["lower", "upper"],
        defaultValue: "lower"
    ) == nil)
    #expect(ProfileV3StateAuthoringPolicy.enumValidationError(
        values: [],
        defaultValue: ""
    ) != nil)
    #expect(ProfileV3StateAuthoringPolicy.enumValidationError(
        values: [""],
        defaultValue: ""
    ) != nil)
    #expect(ProfileV3StateAuthoringPolicy.enumValidationError(
        values: ["a", "a"],
        defaultValue: "a"
    ) != nil)
    #expect(ProfileV3StateAuthoringPolicy.enumValidationError(
        values: ["a", "b"],
        defaultValue: "missing"
    ) != nil)
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
func deletingNonDefaultKeepsDefault() {
    let result = ProfileV3StateAuthoringPolicy.deletingValue(
        at: 1,
        from: ["a", "b", "c"],
        defaultValue: "a",
        replacementDefault: nil
    )
    #expect(result?.values == ["a", "c"])
    #expect(result?.defaultValue == "a")
}
