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
