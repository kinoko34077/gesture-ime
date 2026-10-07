import Testing
@testable import GestureIMEProfileAuthoring

@Test
func macroIDsAreGeneratedInternally() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.macro.id",
        name: "Macro IDs"
    )

    #expect(try document.v3NewMacroID() == "macro.macro-1")

    try document.v3UpsertMacro(
        id: "macro.macro-1",
        actions: []
    )

    #expect(try document.v3NewMacroID() == "macro.macro-2")
}

@Test
func macroDuplicatePreservesUnknownMembersAndActionExtras() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.macro.duplicate",
        name: "Macro Duplicate"
    )

    try document.v3SetSemanticSectionNode(
        .macros,
        node: .array([
            .object([
                "id": .string("macro.source"),
                "futureMacro": .object([
                    "keep": .bool(true)
                ]),
                "actions": .array([
                    .object([
                        "actionID": .string("text.insert"),
                        "arguments": .object([
                            "text": .string("A")
                        ]),
                        "futureAction": .integer(7)
                    ])
                ])
            ])
        ])
    )

    let newID = try document.v3NewMacroID()
    try document.v3DuplicateMacro(
        sourceID: "macro.source",
        newID: newID
    )

    let node = try document.v3SemanticSectionNode(.macros)
    let macros = try #require(node.arrayValue)
    let copy = try #require(
        macros.first(where: {
            $0.objectValue?["id"]?.stringValue == newID
        })?.objectValue
    )

    #expect(
        copy["futureMacro"]
            == .object(["keep": .bool(true)])
    )

    let action = try #require(
        copy["actions"]?.arrayValue?.first?.objectValue
    )
    #expect(action["futureAction"] == .integer(7))
}

@Test
func ordinaryMacroUpdateKeepsMacroLevelUnknownMembers() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.macro.update",
        name: "Macro Update"
    )

    try document.v3SetSemanticSectionNode(
        .macros,
        node: .array([
            .object([
                "id": .string("macro.source"),
                "futureMacro": .string("keep"),
                "actions": .array([])
            ])
        ])
    )

    try document.v3UpsertMacro(
        id: "macro.source",
        actions: [
            ProfileActionDraft(
                actionID: "edit.delete",
                arguments: [
                    "count": .integer(1)
                ]
            )
        ]
    )

    let node = try document.v3SemanticSectionNode(.macros)
    let object = try #require(
        node.arrayValue?.first?.objectValue
    )
    #expect(object["futureMacro"] == .string("keep"))
    #expect(
        object["actions"]?.arrayValue?.count == 1
    )
}

@Test
func malformedMacroActionsAreMarkedReadOnlyBySummary() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.macro.lock",
        name: "Macro Lock"
    )

    try document.v3SetSemanticSectionNode(
        .macros,
        node: .array([
            .object([
                "id": .string("macro.locked"),
                "actions": .array([
                    .object([
                        "arguments": .object([:])
                    ]),
                    .object([
                        "actionID": .string("edit.delete"),
                        "arguments": .object([
                            "count": .integer(1)
                        ])
                    ])
                ])
            ])
        ])
    )

    let macro = try #require(
        document.v3MacroSummaries().first
    )

    #expect(!macro.actionsEditable)
    #expect(macro.actions.count == 1)
    #expect(macro.actions[0].actionID == "edit.delete")
}
