import Foundation
import Testing
@testable import GestureIMEProfileAuthoring

private func v3JSON(_ document: ProfileDocument) throws -> [String: Any] {
    let data = try document.encoded(pretty: false)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

private func v3DefaultResolver(
    text: String? = nil,
    transition: ProfileV3TransitionDraft? = nil
) -> JSONNode {
    var behavior: [String: JSONNode] = [:]
    if let text {
        behavior["presentation"] = .object([
            "text": .object([
                "base": .string(text),
                "transforms": .array([])
            ])
        ])
    }
    if let transition {
        behavior["transition"] = .object([
            "targetBoardRef": .string(transition.targetBoardID),
            "lifetime": .string(transition.lifetime.rawValue)
        ])
    }
    return .object([
        "cases": .array([]),
        "default": .object(behavior)
    ])
}

@Test
func emptyV3SeedAndGesturePolicyUseCanonicalV3Shape() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.empty",
        name: "Empty V3"
    )

    #expect(document.isProfileV3)
    let initialLayerID = try document.v3InitialLayerID()
    #expect(initialLayerID == "layer.base")

    let layers = try document.v3LayerSummaries()
    #expect(layers.count == 1)
    #expect(layers[0].rootBoardID == "board.base")
    #expect(layers[0].isInitial)

    let boards = try document.v3BoardSummaries()
    #expect(boards.count == 1)
    #expect(boards[0].entryCount == 0)

    var policy = try document.gesturePolicy()
    #expect(policy.stage1CommitDistance == 0.55)
    #expect(policy.stage2CommitDistance == 0.45)
    #expect(policy.maxDirectionalStages == 16)

    policy.deadZone = 0.2
    policy.stage1CommitDistance = 0.6
    policy.stage2CommitDistance = 0.5
    try document.setGesturePolicy(policy)

    let object = try v3JSON(document)
    let serialized = try #require(object["gesturePolicy"] as? [String: Any])
    #expect(serialized["initialCellCommitDistance"] as? Double == 0.6)
    #expect(serialized["subsequentCellCommitDistance"] as? Double == 0.5)
    #expect(serialized["stage1CommitDistance"] == nil)
    #expect(serialized["maxDirectionalStages"] == nil)
}

@Test
func v3LayerLifecycleProtectsInitialLayerAndDuplicatesOnlyRootBoard() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.layers",
        name: "Layers"
    )

    try document.v3CreateBoard(id: "board.shared")
    try document.v3CreateEntry(
        boardID: "board.base",
        id: "root.self",
        rect: ProfileV3Rect(x: -1, y: -1, width: 2, height: 2),
        resolver: v3DefaultResolver(
            transition: ProfileV3TransitionDraft(
                targetBoardID: "board.base",
                lifetime: .persistent
            )
        )
    )
    try document.v3CreateEntry(
        boardID: "board.base",
        id: "root.shared",
        rect: ProfileV3Rect(x: 2, y: 0, width: 2, height: 2),
        resolver: v3DefaultResolver(
            transition: ProfileV3TransitionDraft(
                targetBoardID: "board.shared",
                lifetime: .transient
            )
        )
    )

    try document.v3DuplicateLayer(
        sourceLayerID: "layer.base",
        newLayerID: "layer.copy",
        newName: "Copy",
        newRootBoardID: "board.copy"
    )

    let copyEntries = try document.v3BoardEntries(boardID: "board.copy")
    #expect(copyEntries.count == 2)
    #expect(
        copyEntries.first(where: { $0.id == "root.self" })?.transition?.targetBoardID
            == "board.copy"
    )
    #expect(
        copyEntries.first(where: { $0.id == "root.shared" })?.transition?.targetBoardID
            == "board.shared"
    )

    #expect(throws: ProfileAuthoringError.self) {
        try document.v3DeleteLayer(id: "layer.base")
    }

    try document.v3SetInitialLayer("layer.copy")
    try document.v3DeleteLayer(id: "layer.base")
    let initialAfterDelete = try document.v3InitialLayerID()
    let layersAfterDelete = try document.v3LayerSummaries()
    #expect(initialAfterDelete == "layer.copy")
    #expect(layersAfterDelete.map(\.id) == ["layer.copy"])
}

@Test
func v3BoardDuplicationRetargetsOnlySelfReferencesAndDeletionIsReferenceSafe() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.boards",
        name: "Boards"
    )
    try document.v3CreateBoard(id: "board.other")
    try document.v3CreateBoard(id: "board.source")

    try document.v3CreateEntry(
        boardID: "board.source",
        id: "self",
        rect: ProfileV3Rect(x: -1, y: -1, width: 2, height: 2),
        resolver: v3DefaultResolver(
            transition: ProfileV3TransitionDraft(
                targetBoardID: "board.source",
                lifetime: .persistent
            )
        )
    )
    try document.v3CreateEntry(
        boardID: "board.source",
        id: "other",
        rect: ProfileV3Rect(x: 2, y: 0, width: 2, height: 2),
        resolver: v3DefaultResolver(
            transition: ProfileV3TransitionDraft(
                targetBoardID: "board.other",
                lifetime: .transient
            )
        )
    )

    try document.v3DuplicateBoard(
        sourceBoardID: "board.source",
        newBoardID: "board.copy"
    )

    let copy = try document.v3BoardEntries(boardID: "board.copy")
    #expect(
        copy.first(where: { $0.id == "self" })?.transition?.targetBoardID
            == "board.copy"
    )
    #expect(
        copy.first(where: { $0.id == "other" })?.transition?.targetBoardID
            == "board.other"
    )

    let otherRefs = try document.v3InboundReferences(to: "board.other")
    #expect(otherRefs.count == 2)
    #expect(otherRefs.allSatisfy { $0.kind == .entryTransition })

    #expect(throws: ProfileAuthoringError.self) {
        try document.v3DeleteBoard(id: "board.other")
    }

    try document.v3CreateBoard(id: "board.unused")
    try document.v3DeleteBoard(id: "board.unused")
    let boardsAfterDelete = try document.v3BoardSummaries()
    #expect(!boardsAfterDelete.contains(where: { $0.id == "board.unused" }))
}

@Test
func v3InboundReferencesIncludeLayerDefaultCaseAndHoldTransitions() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.refs",
        name: "Refs"
    )
    try document.v3CreateBoard(id: "board.target")
    try document.v3CreateBoard(id: "board.hold")
    try document.v3CreateEntry(
        boardID: "board.base",
        id: "entry.refs",
        rect: ProfileV3Rect(x: -1, y: -1, width: 2, height: 2)
    )

    let resolver: JSONNode = .object([
        "cases": .array([
            .object([
                "when": .object(["fact": .string("conversion.active")]),
                "behavior": .object([
                    "transition": .object([
                        "targetBoardRef": .string("board.target"),
                        "lifetime": .string("transient")
                    ])
                ])
            ])
        ]),
        "default": .object([
            "transition": .object([
                "targetBoardRef": .string("board.target"),
                "lifetime": .string("persistent")
            ]),
            "hold": .object([
                "delayMs": .integer(400),
                "onStart": .array([]),
                "transition": .object([
                    "targetBoardRef": .string("board.hold"),
                    "lifetime": .string("transient")
                ]),
                "suppressOnReleaseAfterStart": .bool(true)
            ])
        ])
    ])
    try document.v3SetEntryResolver(
        boardID: "board.base",
        entryID: "entry.refs",
        resolver: resolver
    )

    let targetRefs = try document.v3InboundReferences(to: "board.target")
    #expect(targetRefs.count == 2)
    #expect(targetRefs.contains(where: { $0.path.contains("resolver.default") }))
    #expect(targetRefs.contains(where: { $0.path.contains("resolver.cases[0]") }))

    let holdRefs = try document.v3InboundReferences(to: "board.hold")
    #expect(holdRefs.count == 1)
    #expect(holdRefs[0].kind == .holdTransition)

    let baseRefs = try document.v3InboundReferences(to: "board.base")
    #expect(baseRefs.contains(where: { $0.kind == .layerRoot }))
}

@Test
func v3AtomicRectMutationsPreserveHalfSpansAndRejectInvalidGeometry() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.geometry",
        name: "Geometry"
    )

    try document.v3CreateEntry(
        boardID: "board.base",
        id: "half",
        rect: ProfileV3Rect(x: 0, y: 0, width: 1, height: 2)
    )
    try document.v3CreateEntry(
        boardID: "board.base",
        id: "span",
        rect: ProfileV3Rect(x: 2, y: 0, width: 4, height: 2)
    )

    var entries = try document.v3BoardEntries(boardID: "board.base")
    #expect(entries.first(where: { $0.id == "half" })?.rect.width == 1)
    #expect(entries.first(where: { $0.id == "span" })?.rect.width == 4)

    #expect(throws: ProfileAuthoringError.self) {
        try document.v3CreateEntry(
            boardID: "board.base",
            id: "overlap",
            rect: ProfileV3Rect(x: 0, y: 1, width: 2, height: 2)
        )
    }

    #expect(throws: ProfileAuthoringError.self) {
        try document.v3SetEntryRect(
            boardID: "board.base",
            entryID: "half",
            rect: ProfileV3Rect(x: 20, y: 0, width: 1, height: 1)
        )
    }

    try document.v3SetEntryRect(
        boardID: "board.base",
        entryID: "span",
        rect: ProfileV3Rect(x: 5, y: 0, width: 4, height: 2)
    )
    entries = try document.v3BoardEntries(boardID: "board.base")
    #expect(entries.first(where: { $0.id == "span" })?.rect.x == 5)

    var extent = try ProfileDocument.emptyV3(id: "extent", name: "Extent")
    try extent.v3CreateEntry(
        boardID: "board.base",
        id: "west",
        rect: ProfileV3Rect(x: -20, y: 0, width: 1, height: 1)
    )
    #expect(throws: ProfileAuthoringError.self) {
        try extent.v3CreateEntry(
            boardID: "board.base",
            id: "east",
            rect: ProfileV3Rect(x: 1, y: 0, width: 1, height: 1)
        )
    }
}

@Test
func v3DefaultBehaviorEditingCoversPresentationActionsTransitionAndHold() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.behavior",
        name: "Behavior"
    )
    try document.v3CreateBoard(id: "board.target")
    try document.v3CreateEntry(
        boardID: "board.base",
        id: "entry.behavior",
        rect: ProfileV3Rect(x: -1, y: -1, width: 2, height: 2)
    )

    try document.v3SetEntryDefaultPresentation(
        boardID: "board.base",
        entryID: "entry.behavior",
        text: "𛀀",
        accessibilityLabel: "変体仮名"
    )
    try document.v3SetEntryDefaultActions(
        boardID: "board.base",
        entryID: "entry.behavior",
        actions: [
            ProfileActionDraft(
                actionID: "text.insert",
                arguments: [
                    "text": .object([
                        "base": .string("𛀀"),
                        "transforms": .array([])
                    ])
                ]
            )
        ]
    )
    try document.v3SetEntryDefaultTransition(
        boardID: "board.base",
        entryID: "entry.behavior",
        transition: ProfileV3TransitionDraft(
            targetBoardID: "board.target",
            lifetime: .transient
        )
    )
    try document.v3SetEntryDefaultHold(
        boardID: "board.base",
        entryID: "entry.behavior",
        hold: ProfileV3HoldDraft(
            delayMs: 350,
            onStart: [ProfileActionDraft(actionID: "noop")],
            repeatBehavior: ProfileV3RepeatDraft(
                intervalMs: 80,
                actions: [ProfileActionDraft(actionID: "noop")]
            ),
            suppressOnReleaseAfterStart: true
        )
    )

    let behaviorEntries = try document.v3BoardEntries(boardID: "board.base")
    let entry = try #require(
        behaviorEntries.first(where: { $0.id == "entry.behavior" })
    )
    #expect(entry.presentationText == "𛀀")
    #expect(entry.accessibilityLabel == "変体仮名")
    #expect(entry.onRelease.first?.actionID == "text.insert")
    #expect(entry.transition?.targetBoardID == "board.target")
    #expect(entry.hold?.delayMs == 350)
    #expect(entry.hold?.repeatIntervalMs == 80)
    #expect(entry.hold?.suppressOnReleaseAfterStart == true)

    #expect(throws: ProfileAuthoringError.self) {
        try document.v3SetEntryDefaultHold(
            boardID: "board.base",
            entryID: "entry.behavior",
            hold: ProfileV3HoldDraft(delayMs: 10)
        )
    }
}

@Test
func v3StateTransformAndMacroEditsPreserveUnicodeAndClearEnumValuesOnBoolean() throws {
    var document = try ProfileDocument.emptyV3(
        id: "user.v3.semantic",
        name: "Semantic"
    )

    try document.v3UpsertEnumState(
        id: "latinCase",
        values: ["lower", "upper"],
        defaultValue: "lower"
    )
    try document.v3UpsertBooleanState(
        id: "latinCase",
        defaultValue: true
    )

    let states = try document.v3StateSummaries()
    let state = try #require(
        states.first(where: { $0.id == "latinCase" })
    )
    #expect(state.type == .boolean)
    #expect(state.values.isEmpty)
    #expect(state.defaultValue == .bool(true))

    let unicodeEntries = [
        ProfileV3TransformEntry(from: "𛀀", to: "𛀁"),
        ProfileV3TransformEntry(from: "が", to: "が"),
        ProfileV3TransformEntry(from: "👩‍💻", to: "🧑‍💻")
    ]
    try document.v3UpsertTransformTable(
        id: "unicode.transform",
        entries: unicodeEntries
    )
    let transformTables = try document.v3TransformTableSummaries()
    #expect(
        transformTables
            .first(where: { $0.id == "unicode.transform" })?
            .entries == unicodeEntries
    )

    #expect(throws: ProfileAuthoringError.self) {
        try document.v3UpsertTransformTable(
            id: "duplicate.transform",
            entries: [
                ProfileV3TransformEntry(from: "か", to: "が"),
                ProfileV3TransformEntry(from: "か", to: "カ")
            ]
        )
    }

    try document.v3UpsertMacro(
        id: "macro.sample",
        actions: [
            ProfileActionDraft(
                actionID: "text.directInsert",
                arguments: [
                    "text": .object([
                        "base": .string("𛀀"),
                        "transforms": .array([])
                    ])
                ]
            )
        ]
    )
    let macros = try document.v3MacroSummaries()
    #expect(
        macros
            .first(where: { $0.id == "macro.sample" })?
            .actions.first?.actionID == "text.directInsert"
    )
}

@Test
func v3UnknownOrdinaryMembersSurviveTargetedEdits() throws {
    let source = """
    {
      "schema":"gesture-ime.profile.v3",
      "id":"user.v3.unknown",
      "name":"Unknown",
      "version":1,
      "gesturePolicy":{
        "deadZone":0.1,
        "initialCellCommitDistance":0.5,
        "subsequentCellCommitDistance":0.4,
        "angularHysteresisDegrees":8
      },
      "initialLayerRef":"layer.base",
      "layers":[
        {
          "id":"layer.base",
          "name":"Base",
          "rootBoardRef":"board.base",
          "futureLayer":{"keep":true}
        }
      ],
      "boards":[
        {
          "id":"board.base",
          "futureBoard":"keep",
          "entries":[
            {
              "id":"entry.one",
              "rect":{"x":-1,"y":-1,"width":2,"height":2,"futureRect":"keep"},
              "resolver":{
                "cases":[],
                "default":{
                  "futureBehavior":"keep"
                },
                "futureResolver":"keep"
              },
              "futureEntry":"keep"
            }
          ]
        }
      ],
      "states":[],
      "transformTables":[],
      "macros":[],
      "futureTop":{"keep":true}
    }
    """

    var document = try ProfileDocument(jsonString: source)
    try document.v3RenameLayer(id: "layer.base", name: "Renamed")
    try document.v3SetEntryRect(
        boardID: "board.base",
        entryID: "entry.one",
        rect: ProfileV3Rect(x: 1, y: 1, width: 2, height: 2)
    )
    try document.v3SetEntryDefaultPresentation(
        boardID: "board.base",
        entryID: "entry.one",
        text: "A",
        accessibilityLabel: nil
    )

    let object = try v3JSON(document)
    #expect((object["futureTop"] as? [String: Any])?["keep"] as? Bool == true)

    let layers = try #require(object["layers"] as? [[String: Any]])
    #expect((layers[0]["futureLayer"] as? [String: Any])?["keep"] as? Bool == true)

    let boards = try #require(object["boards"] as? [[String: Any]])
    #expect(boards[0]["futureBoard"] as? String == "keep")
    let entries = try #require(boards[0]["entries"] as? [[String: Any]])
    #expect(entries[0]["futureEntry"] as? String == "keep")
    let rect = try #require(entries[0]["rect"] as? [String: Any])
    #expect(rect["futureRect"] as? String == "keep")
    let resolver = try #require(entries[0]["resolver"] as? [String: Any])
    #expect(resolver["futureResolver"] as? String == "keep")
    let defaultBehavior = try #require(resolver["default"] as? [String: Any])
    #expect(defaultBehavior["futureBehavior"] as? String == "keep")
}


@Test
func profileDocumentHistoryUndoRedoAndDivergenceAreDeterministic() throws {
    let seed = try ProfileDocument.emptyV3(
        id: "user.v3.history",
        name: "History"
    )
    var history = ProfileDocumentHistory(document: seed, capacity: 3)

    try history.mutate { document in
        try document.rename("One")
    }
    try history.mutate { document in
        try document.v3CreateBoard(id: "board.one")
    }
    try history.mutate { document in
        try document.v3CreateBoard(id: "board.two")
    }

    #expect(history.canUndo)
    #expect(!history.canRedo)
    #expect(history.document.summary.name == "One")
    var historyBoards = try history.document.v3BoardSummaries()
    #expect(historyBoards.contains(where: { $0.id == "board.two" }))

    let firstUndo = history.undo()
    #expect(firstUndo)
    historyBoards = try history.document.v3BoardSummaries()
    #expect(!historyBoards.contains(where: { $0.id == "board.two" }))
    #expect(history.canRedo)

    let firstRedo = history.redo()
    #expect(firstRedo)
    historyBoards = try history.document.v3BoardSummaries()
    #expect(historyBoards.contains(where: { $0.id == "board.two" }))

    let branchUndo = history.undo()
    #expect(branchUndo)
    try history.mutate { document in
        try document.v3CreateBoard(id: "board.branch")
    }
    #expect(!history.canRedo)
    historyBoards = try history.document.v3BoardSummaries()
    #expect(historyBoards.contains(where: { $0.id == "board.branch" }))

    let beforeFailure = history.document
    #expect(throws: ProfileAuthoringError.self) {
        try history.mutate { document in
            try document.v3CreateBoard(id: "board.one")
        }
    }
    #expect(history.document == beforeFailure)
}

@Test
func profileDocumentHistoryCapacityDropsOnlyOldestUndoSnapshot() throws {
    let seed = try ProfileDocument.emptyV3(
        id: "user.v3.history.capacity",
        name: "Zero"
    )
    var history = ProfileDocumentHistory(document: seed, capacity: 2)

    try history.mutate { try $0.rename("One") }
    try history.mutate { try $0.rename("Two") }
    try history.mutate { try $0.rename("Three") }

    let capacityUndoOne = history.undo()
    #expect(capacityUndoOne)
    #expect(history.document.summary.name == "Two")
    let capacityUndoTwo = history.undo()
    #expect(capacityUndoTwo)
    #expect(history.document.summary.name == "One")
    let capacityUndoThree = history.undo()
    #expect(!capacityUndoThree)
}
