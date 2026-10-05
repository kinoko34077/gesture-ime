import Foundation
import Testing
@testable import GestureIMEProfileAuthoring

// #79 — Transform hierarchy is authoring metadata; runtime stays flat.

private func document() throws -> ProfileDocument {
    var document = try ProfileDocument.emptyV3(id: "user.v3.transform", name: "Transform")
    try document.v3UpsertTransformTable(
        id: "kana.small",
        entries: [
            ProfileV3TransformEntry(from: "あ", to: "ぁ"),
            ProfileV3TransformEntry(from: "つ", to: "っ")
        ]
    )
    return document
}

@Test
func legacyFlatTableAppearsUngroupedAndRoundTripsUnchanged() throws {
    var doc = try document()
    let tables = try doc.v3TransformTableRows()
    #expect(tables.count == 1)
    #expect(tables[0].rows.allSatisfy { $0.groupPath.isEmpty })

    let before = try doc.encoded(pretty: false)
    try doc.v3SetTransformTableRows(tables[0])
    #expect(try doc.encoded(pretty: false) == before)
}

@Test
func groupPathPersistsAsMetadataAndFlatMappingIsUnchanged() throws {
    var doc = try document()
    var table = try doc.v3TransformTableRows()[0]
    table.rows[0].groupPath = ["小書き", "あ行"]
    table.rows[1].groupPath = ["小書き", "た行"]
    try doc.v3SetTransformTableRows(table)

    let flat = try doc.v3TransformTableSummaries()[0].entries
    #expect(flat == [
        ProfileV3TransformEntry(from: "あ", to: "ぁ"),
        ProfileV3TransformEntry(from: "つ", to: "っ")
    ])
    #expect(try doc.v3TransformTableRows()[0].rows.map(\.groupPath)
        == [["小書き", "あ行"], ["小書き", "た行"]])

    #expect(throws: ProfileAuthoringError.self) {
        var bad = table
        bad.rows[0].groupPath = ["a/b"]
        try doc.v3SetTransformTableRows(bad)
    }
    #expect(throws: ProfileAuthoringError.self) {
        var bad = table
        bad.rows[1].from = "あ"
        try doc.v3SetTransformTableRows(bad)
    }
}

@Test
func treeNestsGroupsAndSearchRevealsAncestors() throws {
    let aID = UUID()
    let tsuID = UUID()
    let waID = UUID()
    let tables = [
        ProfileV3TransformTableRows(id: "kana.small", rows: [
            .init(from: "あ", to: "ぁ", groupPath: ["小書き", "あ行"], editorID: aID),
            .init(from: "つ", to: "っ", groupPath: ["小書き", "た行"], editorID: tsuID),
            .init(from: "わ", to: "ゎ", editorID: waID)
        ])
    ]
    let tree = ProfileV3TransformGrouping.tree(tables)
    #expect(tree.count == 1)
    let root = tree[0]
    #expect(root.children.map(\.id) == [
        "kana.small/小書き",
        "kana.small/#row-" + waID.uuidString
    ])
    #expect(root.children[0].children.map(\.id) == ["kana.small/小書き/あ行", "kana.small/小書き/た行"])

    let result = ProfileV3TransformGrouping.search("っ", in: tree)
    #expect(result.matches == [
        "kana.small/小書き/た行/#row-" + tsuID.uuidString
    ])
    #expect(result.expanded == ["kana.small", "kana.small/小書き", "kana.small/小書き/た行"])
    #expect(ProfileV3TransformGrouping.search("  ", in: tree).matches.isEmpty)
}

@Test
func csvRoundTripPreservesTableGroupPathAndUnicode() throws {
    let tables = [
        ProfileV3TransformTableRows(id: "t.one", rows: [
            .init(from: "か", to: "が", groupPath: ["濁点", "か行"]),
            .init(from: "a,b", to: "\"Q\"", groupPath: []),
            .init(from: "👩‍👩‍👧", to: "e\u{301}", groupPath: ["絵文字"]),
            .init(from: "line", to: "x\ny", groupPath: [])
        ]),
        ProfileV3TransformTableRows(id: "t.two", rows: [.init(from: " sp", to: "sp ")])
    ]
    let csv = ProfileV3TransformCSV.export(tables)
    #expect(csv.hasPrefix("table,title,groupPath,from,to,reverse\r\n"))
    let parsed = try ProfileV3TransformCSV.parse(csv)
    #expect(parsed == tables)
    #expect(try ProfileV3TransformCSV.parse("\u{FEFF}" + csv) == tables)

    // LF-only input from other tools is accepted too.
    let lf = "table,groupPath,from,to\nt,,a,b\n"
    #expect(try ProfileV3TransformCSV.parse(lf) == [.init(id: "t", rows: [.init(from: "a", to: "b")])])
}

@Test
func csvRejectsBadHeaderDuplicatesAndShortRowsWithoutMutation() throws {
    #expect(throws: ProfileAuthoringError.self) {
        try ProfileV3TransformCSV.parse("from,to\r\na,b\r\n")
    }
    #expect(throws: ProfileAuthoringError.self) {
        try ProfileV3TransformCSV.parse("table,groupPath,from,to\r\nt,,a,b\r\nt,,a,c\r\n")
    }
    #expect(throws: ProfileAuthoringError.self) {
        try ProfileV3TransformCSV.parse("table,groupPath,from,to\r\nt,,a\r\n")
    }
    #expect(throws: ProfileAuthoringError.self) {
        try ProfileV3TransformCSV.parse("table,groupPath,from,to\r\nt,,\"a,b\r\n")
    }

    var doc = try document()
    let before = try doc.encoded(pretty: false)
    #expect(throws: ProfileAuthoringError.self) {
        try doc.v3ApplyTransformCSV([
            .init(id: "kana.small", rows: [.init(from: "x", to: "y")]),
            .init(id: "bad id!", rows: [])
        ])
    }
    #expect(try doc.encoded(pretty: false) == before, "apply is atomic")
}

// MARK: - #101 / frozen #95 §F6

@Test
func titleRenameKeepsInternalIDAndNewIDsAreGenerated() throws {
    var doc = try document()
    var table = try doc.v3TransformTableRows()[0]
    table.title = "小書き"
    try doc.v3SetTransformTableRows(table)
    table.title = "小さい文字"
    try doc.v3SetTransformTableRows(table)
    let reread = try doc.v3TransformTableRows()[0]
    #expect(reread.id == "kana.small")
    #expect(reread.displayTitle == "小さい文字")
    #expect(try doc.v3NewTransformTableID() == "tt.table-1")
}

@Test
func draftRowsAreNeverSerializedAndBlankStartsEmpty() throws {
    var doc = try document()
    var table = try doc.v3TransformTableRows()[0]
    let draft = table.addDraftRow(in: [])
    #expect(table.rows.first { $0.editorID == draft }?.from == "")
    let before = try doc.encoded(pretty: false)
    try doc.v3SetTransformTableRows(table)
    #expect(try doc.encoded(pretty: false) == before, "draft row not persisted")
    #expect(ProfileV3TransformCSV.export([table]).split(separator: "\r\n").count == 3)
}

@Test
func reverseFlagsPersistAndConflictsAreRejected() throws {
    var doc = try document()
    var table = try doc.v3TransformTableRows()[0]
    table.rows[0].reverse = true
    try doc.v3SetTransformTableRows(table)
    #expect(try doc.v3TransformTableRows()[0].rows[0].reverse)

    table.reverseAll = true
    try doc.v3SetTransformTableRows(table)
    let reread = try doc.v3TransformTableRows()[0]
    #expect(reread.reverseAll)
    #expect(reread.effectiveReverse(reread.rows[1]))

    var conflict = reread
    conflict.rows.append(ProfileV3TransformRow(from: "ぁ", to: "x"))
    #expect(throws: ProfileAuthoringError.self) { try doc.v3SetTransformTableRows(conflict) }
}

@Test
func groupNodesPersistIncludingEmptyGroupsAndRenameRewritesMembers() throws {
    var doc = try document()
    var table = try doc.v3TransformTableRows()[0]
    try table.addGroup(named: "小書き")
    try table.addGroup(named: "空のグループ")
    table.moveRow(editorID: table.rows[0].editorID, to: ["小書き"])
    try table.renameGroup(["小書き"], to: "小さい")
    try doc.v3SetTransformTableRows(table)

    let reread = try doc.v3TransformTableRows()[0]
    #expect(reread.groups == [["小さい"], ["空のグループ"]])
    #expect(reread.rows[0].groupPath == ["小さい"])
    let tree = ProfileV3TransformGrouping.tree([reread])
    #expect(Array(tree[0].children.map(\.id).prefix(2)) == ["kana.small/小さい", "kana.small/空のグループ"])

    var deleted = reread
    deleted.deleteGroup(["小さい"])
    #expect(deleted.rows[0].groupPath.isEmpty)
    #expect(deleted.groups == [["空のグループ"]])
    #expect(throws: ProfileAuthoringError.self) { try deleted.addGroup(named: "空のグループ") }
}

@Test
func csvV2RoundTripsTitleAndReverseAndV1StillImports() throws {
    let tables = [ProfileV3TransformTableRows(id: "t", title: "表", rows: [
        .init(from: "a", to: "A", groupPath: ["g"], reverse: true),
        .init(from: "b", to: "B")
    ])]
    let parsed = try ProfileV3TransformCSV.parse(ProfileV3TransformCSV.export(tables))
    #expect(parsed == tables)
    let v1 = try ProfileV3TransformCSV.parse("table,groupPath,from,to\r\nt,,a,A\r\n")
    #expect(v1[0].rows[0].reverse == false && v1[0].title == nil)
    #expect(throws: ProfileAuthoringError.self) {
        try ProfileV3TransformCSV.parse("table,title,groupPath,from,to,reverse\r\nt,,,a,A,maybe\r\n")
    }
}


@Test
func rowIdentitySurvivesFromEditAndDocumentRefresh() throws {
    let first = UUID()
    let second = UUID()
    let previous = ProfileV3TransformTableRows(id: "t", rows: [
        .init(from: "a", to: "A", editorID: first),
        .init(from: "b", to: "B", editorID: second)
    ])
    let loaded = ProfileV3TransformTableRows(id: "t", rows: [
        .init(from: "aa", to: "A"),
        .init(from: "b", to: "B")
    ])
    let reconciled = loaded.preservingEditorIDs(from: previous)
    #expect(reconciled.rows[0].editorID == first)
    #expect(reconciled.rows[1].editorID == second)
    #expect(ProfileV3TransformGrouping.leafID(reconciled.rows[0], prefix: "t")
        == "t/#row-" + first.uuidString)
}

@Test
func identityReconciliationPrefersSemanticMatchAfterDeletion() {
    let first = UUID()
    let second = UUID()
    let third = UUID()
    let previous = ProfileV3TransformTableRows(id: "t", rows: [
        .init(from: "a", to: "A", editorID: first),
        .init(from: "b", to: "B", editorID: second),
        .init(from: "c", to: "C", editorID: third)
    ])
    let loaded = ProfileV3TransformTableRows(id: "t", rows: [
        .init(from: "a", to: "A"),
        .init(from: "c", to: "C")
    ])
    let reconciled = loaded.preservingEditorIDs(from: previous)
    #expect(reconciled.rows.map(\.editorID) == [first, third])
}

@Test
func groupSubtreeMoveAndSiblingReorderAreDeterministic() throws {
    var table = ProfileV3TransformTableRows(
        id: "t",
        groups: [["A"], ["A", "one"], ["A", "two"], ["B"], ["C"]],
        rows: [
            .init(from: "a", to: "A", groupPath: ["A", "one"]),
            .init(from: "b", to: "B", groupPath: ["A", "two"])
        ]
    )

    #expect(table.canReorderGroup(["B"], by: 1))
    let reordered = table.reorderGroup(["B"], by: 1)
    #expect(reordered)
    let rootTree = ProfileV3TransformGrouping.tree([table])[0]
    let rootGroups = rootTree.children.compactMap { node -> String? in
        if case .group(let name) = node.kind { return name }
        return nil
    }
    #expect(rootGroups.prefix(3) == ["A", "C", "B"])

    try table.moveGroup(["A", "one"], to: ["B"])
    #expect(table.rows[0].groupPath == ["B", "one"])
    #expect(table.groups.contains(["B", "one"]))
    #expect(!table.groups.contains(["A", "one"]))
    #expect(throws: ProfileAuthoringError.self) {
        try table.moveGroup(["B"], to: ["B", "one"])
    }
}


@Test
func incompleteExistingEditStaysTransientAndCannotDeletePersistedMapping() {
    let id = UUID()
    let persisted = ProfileV3TransformTableRows(id: "t", rows: [
        .init(from: "a", to: "A", editorID: id)
    ])
    let incomplete = ProfileV3TransformRow(from: "", to: "A", editorID: id)
    #expect(ProfileV3TransformEditPolicy.persistenceCandidate(for: incomplete, in: persisted) == nil)
    #expect(persisted.rows.map(\.from) == ["a"])
}

@Test
func draftPromotionProducesCandidateButRejectedCandidateDoesNotMutateDocument() throws {
    var doc = try document()
    let persisted = try doc.v3TransformTableRows()[0]
    let draft = ProfileV3TransformRow(from: "あ", to: "x")
    let candidate = try #require(
        ProfileV3TransformEditPolicy.persistenceCandidate(for: draft, in: persisted)
    )
    let before = try doc.encoded(pretty: false)
    #expect(throws: ProfileAuthoringError.self) {
        try doc.v3SetTransformTableRows(candidate)
    }
    #expect(try doc.encoded(pretty: false) == before)
    #expect(draft.from == "あ" && draft.to == "x")
}
