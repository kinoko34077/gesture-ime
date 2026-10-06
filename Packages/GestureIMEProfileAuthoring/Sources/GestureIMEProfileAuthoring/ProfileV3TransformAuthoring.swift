import Foundation

// #79 → #101 / frozen #95 §F6 — TransformTable authoring v2.
//
// Ownership (§F6.1):
//   semantic Profile data      : table `id`, row `from`/`to`, `reverseAll`, row `reverse`
//   persistent authoring meta  : table `title`, row `groupPath`, table `authoringGroups`
//   transient editor state     : row `editorID`, draft (blank) rows, disclosure/search
// The runtime compiles `reverse`/`reverseAll` into its flat map (Rust); grouping
// and titles never change transform resolution.

public struct ProfileV3TransformRow: Identifiable, Equatable, Sendable {
    public var from: String
    public var to: String
    /// Nested authoring group names, outermost first. Empty = ungrouped.
    public var groupPath: [String]
    /// Row-level reverse (semantic). Effective = table.reverseAll || reverse.
    public var reverse: Bool
    /// Transient per-session identity; never persisted (§F6.2).
    public let editorID: UUID

    public init(
        from: String,
        to: String,
        groupPath: [String] = [],
        reverse: Bool = false,
        editorID: UUID = UUID()
    ) {
        self.from = from
        self.to = to
        self.groupPath = groupPath
        self.reverse = reverse
        self.editorID = editorID
    }

    public var id: UUID { editorID }

    /// §F6.5: a row becomes semantic only when both sides are non-empty.
    public var isDraft: Bool { from.isEmpty || to.isEmpty }

    public func withEditorID(_ id: UUID) -> Self {
        ProfileV3TransformRow(
            from: from,
            to: to,
            groupPath: groupPath,
            reverse: reverse,
            editorID: id
        )
    }

    /// Equality is semantic + metadata; transient identity is ignored.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.from == rhs.from && lhs.to == rhs.to
            && lhs.groupPath == rhs.groupPath && lhs.reverse == rhs.reverse
    }
}

public struct ProfileV3TransformTableRows: Identifiable, Equatable, Sendable {
    public let id: String
    /// User-visible title (authoring metadata). nil ⇒ UI falls back to id.
    public var title: String?
    public var reverseAll: Bool
    /// Ordered declared groups, including empty ones (authoring metadata).
    public var groups: [[String]]
    public var rows: [ProfileV3TransformRow]

    public init(
        id: String,
        title: String? = nil,
        reverseAll: Bool = false,
        groups: [[String]] = [],
        rows: [ProfileV3TransformRow]
    ) {
        self.id = id
        self.title = title
        self.reverseAll = reverseAll
        self.groups = groups
        self.rows = rows
        repairGroups()
    }

    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return id
    }

    /// Ordinary authoring never falls back to the internal semantic ID.
    /// Position is presentation-only and does not affect identity/runtime.
    public func ordinaryTitle(position: Int) -> String {
        if let title, !title.isEmpty { return title }
        return "変換表 \(max(0, position) + 1)"
    }

    public func effectiveReverse(_ row: ProfileV3TransformRow) -> Bool {
        reverseAll || row.reverse
    }

    /// §F6.4 deterministic repair: every row path (and its ancestors) is declared.
    public mutating func repairGroups() {
        for row in rows where !row.groupPath.isEmpty {
            for depth in 1...row.groupPath.count {
                let path = Array(row.groupPath.prefix(depth))
                if !groups.contains(path) { groups.append(path) }
            }
        }
    }

    // MARK: group operations (authoring metadata only)

    public mutating func addGroup(named name: String, under parent: [String] = []) throws {
        let path = parent + [name]
        try ProfileV3TransformGrouping.validate(groupPath: path)
        guard !groups.contains(path) else {
            throw ProfileAuthoringError.invalidJSON("同じ名前のグループがあります")
        }
        if !parent.isEmpty && !groups.contains(parent) { groups.append(parent) }
        groups.append(path)
    }

    public mutating func renameGroup(_ path: [String], to name: String) throws {
        guard let last = path.indices.last else { return }
        var renamed = path
        renamed[last] = name
        try ProfileV3TransformGrouping.validate(groupPath: renamed)
        guard renamed == path || !groups.contains(renamed) else {
            throw ProfileAuthoringError.invalidJSON("同じ名前のグループがあります")
        }
        func rewrite(_ p: [String]) -> [String] {
            p.starts(with: path) ? renamed + p.dropFirst(path.count) : p
        }
        groups = groups.map(rewrite)
        for index in rows.indices { rows[index].groupPath = rewrite(rows[index].groupPath) }
    }

    /// Deletes a group; its rows and subgroups move up to the parent.
    public mutating func deleteGroup(_ path: [String]) {
        let parent = Array(path.dropLast())
        func lift(_ p: [String]) -> [String] {
            p.starts(with: path) ? parent + p.dropFirst(path.count) : p
        }
        groups = groups.filter { $0 != path }.map(lift)
        var seen: [[String]] = []
        groups = groups.filter { g in
            if seen.contains(g) || g.isEmpty { return false }
            seen.append(g)
            return true
        }
        for index in rows.indices { rows[index].groupPath = lift(rows[index].groupPath) }
    }

    public mutating func moveRow(editorID: UUID, to path: [String]) {
        guard let index = rows.firstIndex(where: { $0.editorID == editorID }) else { return }
        rows[index].groupPath = path
        repairGroups()
    }

    public func canReorderGroup(_ path: [String], by offset: Int) -> Bool {
        guard offset == -1 || offset == 1, groups.contains(path), !path.isEmpty else { return false }
        let parent = Array(path.dropLast())
        let siblings = groups.filter {
            $0.count == path.count && Array($0.dropLast()) == parent
        }
        guard let index = siblings.firstIndex(of: path) else { return false }
        return siblings.indices.contains(index + offset)
    }

    /// Reorders one group among siblings while keeping its declared subtree
    /// together. Runtime mappings are untouched.
    @discardableResult
    public mutating func reorderGroup(_ path: [String], by offset: Int) -> Bool {
        guard canReorderGroup(path, by: offset) else { return false }
        let parent = Array(path.dropLast())
        let siblings = groups.filter {
            $0.count == path.count && Array($0.dropLast()) == parent
        }
        guard let siblingIndex = siblings.firstIndex(of: path) else { return false }
        let target = siblings[siblingIndex + offset]

        let moving = groups.filter { $0.starts(with: path) }
        groups.removeAll { $0.starts(with: path) }

        if offset < 0 {
            guard let insertion = groups.firstIndex(where: { $0.starts(with: target) }) else { return false }
            groups.insert(contentsOf: moving, at: insertion)
        } else {
            let targetIndices = groups.indices.filter { groups[$0].starts(with: target) }
            let insertion = (targetIndices.last.map { $0 + 1 }) ?? groups.endIndex
            groups.insert(contentsOf: moving, at: insertion)
        }
        return true
    }

    /// Moves a whole group subtree under another declared parent. Passing []
    /// moves it to the table root. The group name itself is retained.
    public mutating func moveGroup(_ path: [String], to parent: [String]) throws {
        guard let name = path.last, groups.contains(path) else {
            throw ProfileAuthoringError.invalidJSON("移動するグループが見つかりません")
        }
        guard parent.isEmpty || groups.contains(parent) else {
            throw ProfileAuthoringError.invalidJSON("移動先のグループが見つかりません")
        }
        guard !parent.starts(with: path) else {
            throw ProfileAuthoringError.invalidJSON("グループを自分自身の中へ移動できません")
        }
        let oldParent = Array(path.dropLast())
        if parent == oldParent { return }

        let destination = parent + [name]
        guard !groups.contains(destination) else {
            throw ProfileAuthoringError.invalidJSON("移動先に同じ名前のグループがあります")
        }
        try ProfileV3TransformGrouping.validate(groupPath: destination)

        func rewrite(_ value: [String]) -> [String] {
            value.starts(with: path)
                ? destination + value.dropFirst(path.count)
                : value
        }

        let moving = groups.filter { $0.starts(with: path) }.map(rewrite)
        groups.removeAll { $0.starts(with: path) }
        for index in rows.indices {
            rows[index].groupPath = rewrite(rows[index].groupPath)
        }

        let insertion: Int
        if parent.isEmpty {
            insertion = groups.endIndex
        } else {
            let parentSubtree = groups.indices.filter { groups[$0].starts(with: parent) }
            insertion = parentSubtree.last.map { $0 + 1 } ?? groups.endIndex
        }
        groups.insert(contentsOf: moving, at: insertion)
        repairGroups()
    }

    /// Reconciles transient editor UUIDs after the document is reloaded.
    /// Exact semantic/metadata matches win; positional fallback handles an
    /// intentional edit of `from` without coupling identity to that field.
    public func preservingEditorIDs(from previous: Self) -> Self {
        guard id == previous.id else { return self }
        var result = self
        var unused = Set(previous.rows.indices)

        for index in result.rows.indices {
            if let match = unused.first(where: { previous.rows[$0] == result.rows[index] }) {
                result.rows[index] = result.rows[index].withEditorID(previous.rows[match].editorID)
                unused.remove(match)
            } else if previous.rows.indices.contains(index), unused.contains(index) {
                result.rows[index] = result.rows[index].withEditorID(previous.rows[index].editorID)
                unused.remove(index)
            }
        }
        return result
    }

    /// Appends a transient blank draft row in `path` and returns its identity.
    @discardableResult
    public mutating func addDraftRow(in path: [String] = []) -> UUID {
        let row = ProfileV3TransformRow(from: "", to: "", groupPath: path)
        rows.append(row)
        return row.editorID
    }

    /// Semantic + metadata rows that would be persisted (drafts excluded).
    public var persistableRows: [ProfileV3TransformRow] { rows.filter { !$0.isDraft } }
}

/// Persistence policy shared by the ordinary Transform editor.
/// Returning nil means the edit remains transient: incomplete existing rows
/// never remove their persisted mapping, and blank new rows never serialize.
public enum ProfileV3TransformEditPolicy {
    public static func persistenceCandidate(
        for row: ProfileV3TransformRow,
        in persisted: ProfileV3TransformTableRows
    ) -> ProfileV3TransformTableRows? {
        var updated = persisted
        if let index = updated.rows.firstIndex(where: { $0.editorID == row.editorID }) {
            guard !row.isDraft else { return nil }
            updated.rows[index] = row
            return updated
        }
        guard !row.isDraft else { return nil }
        updated.rows.append(row)
        return updated
    }
}

/// Disclosure tree node: a table, a group, or a leaf mapping.
public struct ProfileV3TransformNode: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case table(id: String)
        case group(name: String)
        case leaf(ProfileV3TransformRow)
    }

    /// Stable path key, e.g. "kana.small/あ行" or "kana.small/あ行/#あ".
    public let id: String
    public let kind: Kind
    public var children: [ProfileV3TransformNode]
}

public enum ProfileV3TransformGrouping {
    public static let separator: Character = "/"

    public static func validate(groupPath: [String]) throws {
        for name in groupPath {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed == name, !name.contains(separator),
                  name.unicodeScalars.count <= 64 else {
                throw ProfileAuthoringError.invalidJSON(
                    "グループ名は空白や「/」を含まない1〜64文字で指定してください"
                )
            }
        }
        guard groupPath.count <= 16 else {
            throw ProfileAuthoringError.invalidJSON("グループの入れ子は16段までです")
        }
    }

    public static func encode(_ groupPath: [String]) -> String {
        groupPath.joined(separator: String(separator))
    }

    public static func decode(_ text: String) -> [String] {
        text.isEmpty ? [] : text.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
    }

    /// Builds the disclosure tree: declared groups (incl. empty) in order,
    /// then rows in authored order.
    public static func tree(_ tables: [ProfileV3TransformTableRows]) -> [ProfileV3TransformNode] {
        tables.map { table in
            var root = ProfileV3TransformNode(id: table.id, kind: .table(id: table.id), children: [])
            for group in table.groups {
                ensureGroup(group[...], in: &root, prefix: table.id)
            }
            for row in table.rows {
                insert(row, path: row.groupPath[...], into: &root, prefix: table.id)
            }
            return root
        }
    }

    public static func leafID(_ row: ProfileV3TransformRow, prefix: String) -> String {
        prefix + "/#row-" + row.editorID.uuidString
    }

    private static func ensureGroup(
        _ path: ArraySlice<String>,
        in node: inout ProfileV3TransformNode,
        prefix: String
    ) {
        guard let head = path.first else { return }
        let childID = prefix + "/" + head
        if let index = node.children.firstIndex(where: { $0.id == childID }) {
            ensureGroup(path.dropFirst(), in: &node.children[index], prefix: childID)
        } else {
            var child = ProfileV3TransformNode(id: childID, kind: .group(name: head), children: [])
            ensureGroup(path.dropFirst(), in: &child, prefix: childID)
            node.children.append(child)
        }
    }

    private static func insert(
        _ row: ProfileV3TransformRow,
        path: ArraySlice<String>,
        into node: inout ProfileV3TransformNode,
        prefix: String
    ) {
        guard let head = path.first else {
            node.children.append(ProfileV3TransformNode(
                id: leafID(row, prefix: prefix),
                kind: .leaf(row),
                children: []
            ))
            return
        }
        let childID = prefix + "/" + head
        if let index = node.children.firstIndex(where: { $0.id == childID }) {
            insert(row, path: path.dropFirst(), into: &node.children[index], prefix: childID)
        } else {
            var child = ProfileV3TransformNode(id: childID, kind: .group(name: head), children: [])
            insert(row, path: path.dropFirst(), into: &child, prefix: childID)
            node.children.append(child)
        }
    }

    /// Search: returns the IDs of every ancestor (table/group) that must be
    /// expanded to reveal a matching leaf, plus the matching leaf IDs.
    public static func search(
        _ query: String,
        in nodes: [ProfileV3TransformNode]
    ) -> (expanded: Set<String>, matches: Set<String>) {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return ([], []) }
        var expanded = Set<String>()
        var matches = Set<String>()

        func visit(_ node: ProfileV3TransformNode, ancestors: [String]) -> Bool {
            switch node.kind {
            case .leaf(let row):
                let hit = row.from.contains(needle) || row.to.contains(needle)
                if hit {
                    matches.insert(node.id)
                    expanded.formUnion(ancestors)
                }
                return hit
            case .group(let name):
                var hit = name.contains(needle)
                for child in node.children where visit(child, ancestors: ancestors + [node.id]) {
                    hit = true
                }
                if hit { expanded.formUnion(ancestors) }
                return hit
            case .table(let id):
                var hit = id.contains(needle)
                for child in node.children where visit(child, ancestors: ancestors + [node.id]) {
                    hit = true
                }
                return hit
            }
        }
        for node in nodes { _ = visit(node, ancestors: []) }
        return (expanded, matches)
    }
}

// MARK: - CSV (§F6.6): export v2 `table,title,groupPath,from,to,reverse`;
// import accepts v2 and v1 `table,groupPath,from,to`.

public enum ProfileV3TransformCSV {
    public static let header = ["table", "title", "groupPath", "from", "to", "reverse"]
    public static let legacyHeader = ["table", "groupPath", "from", "to"]

    public static func export(_ tables: [ProfileV3TransformTableRows]) -> String {
        var lines = [header.joined(separator: ",")]
        for table in tables {
            for row in table.persistableRows {
                lines.append([
                    table.id,
                    table.title ?? "",
                    ProfileV3TransformGrouping.encode(row.groupPath),
                    row.from,
                    row.to,
                    row.reverse ? "1" : "0"
                ].map(quote).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Parses and validates without mutating anything; apply is atomic.
    /// `reverseAll` is not part of CSV and is preserved by apply.
    public static func parse(_ text: String) throws -> [ProfileV3TransformTableRows] {
        let records = try records(text)
        guard let first = records.first, first == header || first == legacyHeader else {
            throw ProfileAuthoringError.invalidJSON(
                "CSVの先頭行は table,title,groupPath,from,to,reverse（または table,groupPath,from,to）にしてください"
            )
        }
        let v2 = first == header
        var order: [String] = []
        var rows: [String: [ProfileV3TransformRow]] = [:]
        var titles: [String: String] = [:]
        var seen: [String: Set<String>] = [:]
        for (index, record) in records.dropFirst().enumerated() {
            if record == [""] { continue }
            guard record.count == (v2 ? 6 : 4) else {
                throw ProfileAuthoringError.invalidJSON("CSV \(index + 2)行目: 列数が正しくありません")
            }
            let table = record[0]
            try ProfileDocument.v3ValidateSemanticID(table, field: "table")
            let pathText = v2 ? record[2] : record[1]
            let from = v2 ? record[3] : record[2]
            let to = v2 ? record[4] : record[3]
            let reverse: Bool
            if v2 {
                switch record[5] {
                case "1", "true": reverse = true
                case "", "0", "false": reverse = false
                default:
                    throw ProfileAuthoringError.invalidJSON("CSV \(index + 2)行目: reverse は 0 か 1 です")
                }
                if !record[1].isEmpty { titles[table] = record[1] }
            } else {
                reverse = false
            }
            let path = ProfileV3TransformGrouping.decode(pathText)
            try ProfileV3TransformGrouping.validate(groupPath: path)
            guard !from.isEmpty else {
                throw ProfileAuthoringError.invalidJSON("CSV \(index + 2)行目: 変換前が空です")
            }
            guard seen[table, default: []].insert(from).inserted else {
                throw ProfileAuthoringError.invalidJSON(
                    "CSV \(index + 2)行目: 表 \(table) で変換前「\(from)」が重複しています"
                )
            }
            if rows[table] == nil { order.append(table) }
            rows[table, default: []].append(
                ProfileV3TransformRow(from: from, to: to, groupPath: path, reverse: reverse)
            )
        }
        return order.map {
            ProfileV3TransformTableRows(id: $0, title: titles[$0], rows: rows[$0] ?? [])
        }
    }

    static func quote(_ field: String) -> String {
        let needsQuote = field.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
            || field.hasPrefix(" ") || field.hasSuffix(" ")
        guard needsQuote else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func records(_ text: String) throws -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text.unicodeScalars)[...]
        var lastWasCR = false

        func endField() { record.append(field); field = "" }
        func endRecord() { endField(); records.append(record); record = [] }

        while let scalar = iterator.popFirst() {
            if inQuotes {
                if scalar == "\"" {
                    if iterator.first == "\"" {
                        field.unicodeScalars.append("\"")
                        iterator.removeFirst()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
                lastWasCR = false
                continue
            }
            switch scalar {
            case "\"" where field.isEmpty:
                inQuotes = true
            case ",":
                endField()
            case "\r":
                endRecord()
                lastWasCR = true
                continue
            case "\n":
                if !lastWasCR { endRecord() }
            default:
                field.unicodeScalars.append(scalar)
            }
            lastWasCR = false
        }
        guard !inQuotes else {
            throw ProfileAuthoringError.invalidJSON("CSVの引用符が閉じていません")
        }
        if !field.isEmpty || !record.isEmpty { endRecord() }
        if var first = records.first, let head = first.first, head.hasPrefix("\u{FEFF}") {
            first[0] = String(head.dropFirst())
            records[0] = first
        }
        return records
    }
}

// MARK: - Document operations

extension ProfileDocument {
    public func v3TransformTableRows() throws -> [ProfileV3TransformTableRows] {
        try v3Array(named: "transformTables").compactMap { node in
            guard let object = node.objectValue, let id = object["id"]?.stringValue else {
                return nil
            }
            let rows = (object["entries"]?.arrayValue ?? []).compactMap { entry -> ProfileV3TransformRow? in
                guard let item = entry.objectValue,
                      let from = item["from"]?.stringValue,
                      let to = item["to"]?.stringValue else {
                    return nil
                }
                let path = (item["groupPath"]?.arrayValue ?? []).compactMap(\.stringValue)
                let reverse: Bool
                if case .bool(let value)? = item["reverse"] { reverse = value } else { reverse = false }
                return ProfileV3TransformRow(from: from, to: to, groupPath: path, reverse: reverse)
            }
            let groups = (object["authoringGroups"]?.arrayValue ?? []).compactMap { node -> [String]? in
                let path = (node.arrayValue ?? []).compactMap(\.stringValue)
                return path.isEmpty ? nil : path
            }
            let reverseAll: Bool
            if case .bool(let value)? = object["reverseAll"] { reverseAll = value } else { reverseAll = false }
            return ProfileV3TransformTableRows(
                id: id,
                title: object["title"]?.stringValue,
                reverseAll: reverseAll,
                groups: groups,
                rows: rows
            )
        }
    }

    /// Generated stable internal ID for a new table (§F6.1): never derived
    /// from the (renamable) title.
    public func v3NewTransformTableID() throws -> String {
        let existing = Set(try v3TransformTableRows().map(\.id))
        var index = 1
        while existing.contains("tt.table-\(index)") { index += 1 }
        return "tt.table-\(index)"
    }

    /// Replaces one table (creating it if needed). Draft rows are skipped
    /// (never serialized); unknown entry fields survive for kept sources.
    public mutating func v3SetTransformTableRows(_ table: ProfileV3TransformTableRows) throws {
        try Self.v3ValidateSemanticID(table.id, field: "transformTable.id")
        let rows = table.persistableRows
        guard rows.count <= 2048 else {
            throw ProfileAuthoringError.invalidJSON("変換表は2048行までです")
        }
        if let title = table.title, title.unicodeScalars.count > 64 {
            throw ProfileAuthoringError.invalidJSON("表のタイトルは64文字までです")
        }
        var seen = Set<String>()
        for row in rows {
            guard seen.insert(row.from).inserted else {
                throw ProfileAuthoringError.invalidJSON("変換前「\(row.from)」が重複しています")
            }
            try ProfileV3TransformGrouping.validate(groupPath: row.groupPath)
        }
        // §F6.3 conflict rule mirrored for immediate feedback (Rust stays
        // authoritative at validation).
        var effective: [String: String] = Dictionary(uniqueKeysWithValues: rows.map { ($0.from, $0.to) })
        for row in rows where table.effectiveReverse(row) {
            if let existing = effective[row.to], existing != row.from {
                throw ProfileAuthoringError.invalidJSON(
                    "逆変換「\(row.to)→\(row.from)」が既存の「\(row.to)→\(existing)」と衝突します"
                )
            }
            effective[row.to] = row.from
        }

        var top = try v3TopObject()
        var tables = top["transformTables"]?.arrayValue ?? []
        let index = tables.firstIndex { $0.objectValue?["id"]?.stringValue == table.id }
        var object = index.flatMap { tables[$0].objectValue } ?? ["id": .string(table.id)]
        let previous = Dictionary(
            (object["entries"]?.arrayValue ?? []).compactMap { node -> (String, [String: JSONNode])? in
                guard let item = node.objectValue, let from = item["from"]?.stringValue else { return nil }
                return (from, item)
            },
            uniquingKeysWith: { first, _ in first }
        )
        object["entries"] = .array(rows.map { row in
            var item = previous[row.from] ?? [:]
            item["from"] = .string(row.from)
            item["to"] = .string(row.to)
            if row.groupPath.isEmpty {
                item.removeValue(forKey: "groupPath")
            } else {
                item["groupPath"] = .array(row.groupPath.map(JSONNode.string))
            }
            if row.reverse { item["reverse"] = .bool(true) } else { item.removeValue(forKey: "reverse") }
            return .object(item)
        })
        if let title = table.title, !title.isEmpty {
            object["title"] = .string(title)
        } else {
            object.removeValue(forKey: "title")
        }
        if table.reverseAll { object["reverseAll"] = .bool(true) } else { object.removeValue(forKey: "reverseAll") }
        if table.groups.isEmpty {
            object.removeValue(forKey: "authoringGroups")
        } else {
            object["authoringGroups"] = .array(table.groups.map { .array($0.map(JSONNode.string)) })
        }
        if let index {
            tables[index] = .object(object)
        } else {
            tables.append(.object(object))
        }
        top["transformTables"] = .array(tables)
        root = .object(top)
    }

    /// Applies a parsed CSV atomically: listed tables are replaced (keeping
    /// their existing `reverseAll` and declared groups); others untouched.
    public mutating func v3ApplyTransformCSV(_ tables: [ProfileV3TransformTableRows]) throws {
        let existing = Dictionary(
            (try v3TransformTableRows()).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var candidate = self
        for var table in tables {
            if let old = existing[table.id] {
                table.reverseAll = old.reverseAll
                if table.title == nil { table.title = old.title }
                table.groups = old.groups
                table.repairGroups()
            }
            try candidate.v3SetTransformTableRows(table)
        }
        self = candidate
    }
}
