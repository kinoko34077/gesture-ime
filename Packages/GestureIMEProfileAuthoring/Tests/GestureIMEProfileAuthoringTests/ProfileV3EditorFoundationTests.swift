import Foundation
import Testing
@testable import GestureIMEProfileAuthoring

// #73 — editor foundation: policy UX data, partial overrides, catalog,
// deterministic canvas ownership, stable viewport, direction slots, presets.

private func emptyDocument() throws -> ProfileDocument {
    try ProfileDocument.emptyV3(id: "user.v3.editor", name: "Editor")
}

private func json(_ document: ProfileDocument) throws -> [String: Any] {
    let data = try document.encoded(pretty: false)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func entryObject(
    _ document: ProfileDocument,
    board: String,
    entry: String
) throws -> [String: Any] {
    let boards = try #require(try json(document)["boards"] as? [[String: Any]])
    let target = try #require(boards.first { $0["id"] as? String == board })
    let entries = try #require(target["entries"] as? [[String: Any]])
    return try #require(entries.first { $0["id"] as? String == entry })
}

// MARK: - Policy

@Test
func commonPolicyReadsDefaultDwellAndWritesAllFiveFields() throws {
    var document = try emptyDocument()
    var values = try document.v3GesturePolicyValues()
    #expect(values.stageBacktrackDwellMs == 1000)

    values.stageBacktrackDwellMs = 750
    values.deadZone = 0.2
    try document.v3SetGesturePolicyValues(values)

    let policy = try #require(try json(document)["gesturePolicy"] as? [String: Any])
    #expect(policy["stageBacktrackDwellMs"] as? Int == 750)
    #expect(policy["deadZone"] as? Double == 0.2)
    #expect(try document.v3GesturePolicyValues() == values)

    values.stageBacktrackDwellMs = 50
    #expect(throws: ProfileAuthoringError.self) {
        try document.v3SetGesturePolicyValues(values)
    }
}

@Test
func partialOverrideInheritsUnsetFieldsAndRemovesWhenEmpty() throws {
    var document = try emptyDocument()
    try document.v3CreateEntry(
        boardID: "board.base",
        id: "key",
        rect: ProfileV3Rect(x: -1, y: -1, width: 2, height: 2)
    )
    #expect(try document.v3EntryPolicyOverride(boardID: "board.base", entryID: "key") == nil)

    let partial = ProfileV3GesturePolicyOverride(initialCellCommitDistance: 1.0)
    try document.v3SetEntryPolicyOverride(boardID: "board.base", entryID: "key", override: partial)

    let stored = try entryObject(document, board: "board.base", entry: "key")
    let object = try #require(stored["gesturePolicyOverride"] as? [String: Any])
    #expect(object.keys.sorted() == ["initialCellCommitDistance"])

    let common = try document.v3GesturePolicyValues()
    let effective = common.applying(
        try document.v3EntryPolicyOverride(boardID: "board.base", entryID: "key")
    )
    #expect(effective.initialCellCommitDistance == 1.0)
    #expect(effective.deadZone == common.deadZone)
    #expect(effective.stageBacktrackDwellMs == common.stageBacktrackDwellMs)

    // Merged policy is validated in inherited context.
    #expect(throws: ProfileAuthoringError.self) {
        try document.v3SetEntryPolicyOverride(
            boardID: "board.base",
            entryID: "key",
            override: ProfileV3GesturePolicyOverride(initialCellCommitDistance: 0.01)
        )
    }

    try document.v3SetEntryPolicyOverride(
        boardID: "board.base",
        entryID: "key",
        override: ProfileV3GesturePolicyOverride()
    )
    let cleared = try entryObject(document, board: "board.base", entry: "key")
    #expect(cleared["gesturePolicyOverride"] == nil)
}

// MARK: - Display Catalog

@Test
func displayCatalogIsCompleteJapaneseAndNeverEchoesInternalIDs() throws {
    let asciiAllowed: Set<ProfileV3DisplayKey> = [.presetQwerty]
    for key in ProfileV3DisplayKey.allCases {
        let text = ProfileV3DisplayCatalog.text(key)
        #expect(!text.title.isEmpty, "\(key)")
        #expect(!text.shortLabel.isEmpty, "\(key)")
        #expect(!text.help.isEmpty, "\(key)")
        #expect(text.title != key.rawValue)
        if !asciiAllowed.contains(key) {
            let hasJapanese = text.title.unicodeScalars.contains { $0.value >= 0x3040 }
            #expect(hasJapanese, "\(key) title should be Japanese: \(text.title)")
        }
    }

    #expect(ProfileV3DisplayCatalog.title(.policyDeadZone) == "無反応距離")
    #expect(ProfileV3DisplayCatalog.title(.policyInitialCommit) == "1段階目の確定距離")
    #expect(ProfileV3DisplayCatalog.title(.policySubsequentCommit) == "2段階目以降の確定距離")
    #expect(ProfileV3DisplayCatalog.title(.policyHysteresis) == "方向切替の遊び")
    #expect(ProfileV3DisplayCatalog.title(.policyBacktrackDwell) == "前の段階へ戻るまでの時間")

    for field in ProfileV3GesturePolicyField.allCases {
        #expect(ProfileV3DisplayCatalog.text(field.displayKey).unit != nil)
    }
    #expect(ProfileV3DisplayCatalog.actionTitle("text.insert") == "文字を入力")
    #expect(ProfileV3DisplayCatalog.actionTitle("vendor.unknown") == "その他の動作")
}

// MARK: - Canvas hit-testing / interaction / viewport

private let viewport = ProfileV3CanvasViewport(atomicSize: 20, originX: 200, originY: 200)

private let canvasEntries: [(id: String, rect: ProfileV3Rect)] = [
    ("a", ProfileV3Rect(x: -2, y: -2, width: 2, height: 2)),
    ("b", ProfileV3Rect(x: 0, y: -2, width: 2, height: 2)),
    ("tiny", ProfileV3Rect(x: 4, y: 0, width: 1, height: 1)),
    ("last", ProfileV3Rect(x: 6, y: 4, width: 2, height: 2))
]

@Test
func hitTestingOwnsExactlyTheEntryUnderTheFingerRegardlessOfOrder() throws {
    // Center of "a" and "b" — not the last/topmost entry.
    #expect(ProfileV3CanvasHitTester.hit(
        x: 180, y: 180, entries: canvasEntries, selectedEntryID: nil, viewport: viewport
    ) == .entry(entryID: "a"))
    #expect(ProfileV3CanvasHitTester.hit(
        x: 220, y: 180, entries: canvasEntries, selectedEntryID: nil, viewport: viewport
    ) == .entry(entryID: "b"))

    // Reordering input never changes ownership.
    let reversed = Array(canvasEntries.reversed())
    #expect(ProfileV3CanvasHitTester.hit(
        x: 180, y: 180, entries: reversed, selectedEntryID: nil, viewport: viewport
    ) == .entry(entryID: "a"))

    // A 20pt "tiny" entry is reachable through its 44pt halo.
    #expect(ProfileV3CanvasHitTester.hit(
        x: 290 + 18, y: 210, entries: canvasEntries, selectedEntryID: nil, viewport: viewport
    ) == .entry(entryID: "tiny"))

    // Empty space resolves to its atom.
    #expect(ProfileV3CanvasHitTester.hit(
        x: 205, y: 265, entries: canvasEntries, selectedEntryID: nil, viewport: viewport
    ) == .empty(x: 0, y: 3))
}

@Test
func selectedResizeHandleWinsOverNeighbouringEntry() throws {
    // Bottom-right corner of "a" is (200, 200) — also the corner of "b".
    #expect(ProfileV3CanvasHitTester.hit(
        x: 205, y: 205, entries: canvasEntries, selectedEntryID: "a", viewport: viewport
    ) == .resizeHandle(entryID: "a"))
    #expect(ProfileV3CanvasHitTester.hit(
        x: 205, y: 185, entries: canvasEntries, selectedEntryID: nil, viewport: viewport
    ) == .entry(entryID: "b"))
}

@Test
func interactionDerivesCandidatesFromStartRectWithoutViewportFeedback() throws {
    let move = ProfileV3CanvasInteraction.begin(
        hit: .entry(entryID: "b"), tool: .select, entries: canvasEntries, viewport: viewport
    )
    #expect(move.targetEntryID == "b")
    #expect(move.candidateRect(
        translationX: 41, translationY: -19, currentX: 0, currentY: 0, viewport: viewport
    ) == ProfileV3Rect(x: 2, y: -3, width: 2, height: 2))
    // Same translation again → same candidate (no cumulative drift/jitter).
    #expect(move.candidateRect(
        translationX: 41, translationY: -19, currentX: 0, currentY: 0, viewport: viewport
    ) == ProfileV3Rect(x: 2, y: -3, width: 2, height: 2))

    let resize = ProfileV3CanvasInteraction.begin(
        hit: .resizeHandle(entryID: "a"), tool: .select, entries: canvasEntries, viewport: viewport
    )
    #expect(resize.candidateRect(
        translationX: -200, translationY: 20, currentX: 0, currentY: 0, viewport: viewport
    ) == ProfileV3Rect(x: -2, y: -2, width: 1, height: 3))

    let createInSelect = ProfileV3CanvasInteraction.begin(
        hit: .empty(x: 0, y: 3), tool: .select, entries: canvasEntries, viewport: viewport
    )
    #expect(createInSelect.operation == .none)

    let create = ProfileV3CanvasInteraction.begin(
        hit: .empty(x: 0, y: 3), tool: .create, entries: canvasEntries, viewport: viewport
    )
    #expect(create.candidateRect(
        translationX: 0, translationY: 0, currentX: 245, currentY: 265, viewport: viewport
    ) == ProfileV3Rect(x: 0, y: 3, width: 3, height: 1))

    let pan = ProfileV3CanvasInteraction.begin(
        hit: .entry(entryID: "a"), tool: .pan, entries: canvasEntries, viewport: viewport
    )
    #expect(pan.targetEntryID == nil)
    #expect(pan.pannedViewport(translationX: 10, translationY: -5)
        == ProfileV3CanvasViewport(atomicSize: 20, originX: 210, originY: 195))
}

@Test
func viewportFitsOnlyWhenAskedAndZoomKeepsAnchor() throws {
    let fitted = ProfileV3CanvasViewport.fitting(
        rects: canvasEntries.map(\.rect), width: 400, height: 300
    )
    for item in canvasEntries {
        let frame = fitted.frame(for: item.rect)
        #expect(frame.x >= 0 && frame.y >= 0)
        #expect(frame.x + frame.width <= 400 && frame.y + frame.height <= 300)
    }

    var zoomed = fitted
    let anchorAtomBefore = zoomed.atom(x: 123, y: 77)
    zoomed.zoom(by: 2, anchorX: 123, anchorY: 77)
    #expect(zoomed.atomicSize == min(fitted.atomicSize * 2, 120))
    #expect(zoomed.atom(x: 123, y: 77) == anchorAtomBefore)
}

// MARK: - Direction slots

@Test
func directionSlotsAreViewsOverBoardEntriesIncludingDiagonals() throws {
    var document = try emptyDocument()
    try document.v3CreateBoard(id: "board.flick")
    try document.v3CreateEntry(
        boardID: "board.flick",
        id: "center",
        rect: ProfileV3Rect(x: -1, y: -1, width: 2, height: 2)
    )
    let east = try #require(
        try document.v3SetDirectionText(boardID: "board.flick", direction: .east, text: "え")
    )
    let northEast = try #require(
        try document.v3SetDirectionText(boardID: "board.flick", direction: .northEast, text: "ね")
    )

    let slots = try document.v3ImmediateDirectionSlots(boardID: "board.flick")
    #expect(slots.count == 8)
    #expect(slots.first { $0.direction == .east }?.entry?.id == east)
    #expect(slots.first { $0.direction == .northEast }?.entry?.rect
        == ProfileV3Rect(x: 1, y: -3, width: 2, height: 2))
    #expect(slots.first { $0.direction == .north }?.entry == nil)
    #expect(try document.v3SimpleTextOutput(boardID: "board.flick", entryID: northEast) == "ね")

    // Editing an existing slot rewrites the same entry; nothing else stores direction.
    try document.v3SetDirectionText(boardID: "board.flick", direction: .east, text: "エ")
    #expect(try document.v3SimpleTextOutput(boardID: "board.flick", entryID: east) == "エ")
    let stored = try entryObject(document, board: "board.flick", entry: east)
    #expect(stored["direction"] == nil)

    try document.v3SetDirectionText(boardID: "board.flick", direction: .east, text: nil)
    #expect(try document.v3ImmediateDirectionSlots(boardID: "board.flick")
        .first { $0.direction == .east }?.entry == nil)
}

// MARK: - Presets

@Test(arguments: ProfileV3Preset.allCases)
func presetsGenerateOrdinaryEditableBoards(preset: ProfileV3Preset) throws {
    var document = try emptyDocument()
    let layerID = "layer.\(preset.rawValue)"
    try document.v3CreateLayer(fromPreset: preset, layerID: layerID, name: nil)

    let layer = try #require(try document.v3LayerSummaries().first { $0.id == layerID })
    let rootEntries = try document.v3BoardEntries(boardID: layer.rootBoardID)
    switch preset {
    case .empty:
        #expect(rootEntries.isEmpty)
    case .japanese12, .latin12, .numeric:
        #expect(rootEntries.count == 12)
    case .qwerty:
        #expect(rootEntries.count == 26)
    case .fourWay, .eightWay, .multiStage:
        #expect(rootEntries.count == 1)
    }

    // Every generated transition targets an existing Board.
    let boardIDs = Set(try document.v3BoardSummaries().map(\.id))
    for entry in rootEntries {
        if let target = entry.transition?.targetBoardID {
            #expect(boardIDs.contains(target))
        }
    }

    if preset == .japanese12 {
        let a = try #require(rootEntries.first { $0.presentationText == "あ" })
        let flick = try #require(a.transition?.targetBoardID)
        let slots = try document.v3ImmediateDirectionSlots(boardID: flick)
        let texts = Dictionary(uniqueKeysWithValues: try slots.compactMap { slot -> (ProfileV3Direction, String)? in
            guard let entry = slot.entry,
                  let text = try document.v3SimpleTextOutput(boardID: flick, entryID: entry.id) else {
                return nil
            }
            return (slot.direction, text)
        })
        #expect(texts == [.west: "い", .north: "う", .east: "え", .south: "お"])
    }
    if preset == .eightWay {
        let key = try #require(rootEntries.first)
        let flick = try #require(key.transition?.targetBoardID)
        let slots = try document.v3ImmediateDirectionSlots(boardID: flick)
        #expect(slots.allSatisfy { $0.entry != nil })
    }
}
