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
    let tables = [
        ProfileV3TransformTableRows(id: "kana.small", rows: [
            .init(from: "あ", to: "ぁ", groupPath: ["小書き", "あ行"]),
            .init(from: "つ", to: "っ", groupPath: ["小書き", "た行"]),
            .init(from: "わ", to: "ゎ")
        ])
    ]
    let tree = ProfileV3TransformGrouping.tree(tables)
    #expect(tree.count == 1)
    let root = tree[0]
    #expect(root.children.map(\.id) == ["kana.small/小書き", "kana.small/#わ"])
    #expect(root.children[0].children.map(\.id) == ["kana.small/小書き/あ行", "kana.small/小書き/た行"])

    let result = ProfileV3TransformGrouping.search("っ", in: tree)
    #expect(result.matches == ["kana.small/小書き/た行/#つ"])
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
    #expect(csv.hasPrefix("table,groupPath,from,to\r\n"))
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
