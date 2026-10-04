import Foundation

// #79 / #69 §11 — TransformTable authoring. Runtime tables stay flat,
// deterministic Unicode `from → to` mappings. Grouping is authoring metadata
// (`groupPath` on each entry) that the runtime ignores; disclosure open/closed
// state is editor UI state and is never persisted.

public struct ProfileV3TransformRow: Identifiable, Equatable, Sendable {
    public var from: String
    public var to: String
    /// Nested authoring group names, outermost first. Empty = ungrouped.
    public var groupPath: [String]

    public init(from: String, to: String, groupPath: [String] = []) {
        self.from = from
        self.to = to
        self.groupPath = groupPath
    }

    public var id: String { from }
}

public struct ProfileV3TransformTableRows: Identifiable, Equatable, Sendable {
    public let id: String
    public var rows: [ProfileV3TransformRow]

    public init(id: String, rows: [ProfileV3TransformRow]) {
        self.id = id
        self.rows = rows
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

    /// Builds the disclosure tree. Groups keep first-appearance order; leaves
    /// keep authored order (authoring order never affects runtime matching).
    public static func tree(_ tables: [ProfileV3TransformTableRows]) -> [ProfileV3TransformNode] {
        tables.map { table in
            var root = ProfileV3TransformNode(id: table.id, kind: .table(id: table.id), children: [])
            for row in table.rows {
                insert(row, path: row.groupPath[...], into: &root, prefix: table.id)
            }
            return root
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
                id: prefix + "/#" + row.from,
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

// MARK: - CSV `table,groupPath,from,to` (RFC 4180 quoting, UTF-8)

public enum ProfileV3TransformCSV {
    public static let header = ["table", "groupPath", "from", "to"]

    public static func export(_ tables: [ProfileV3TransformTableRows]) -> String {
        var lines = [header.joined(separator: ",")]
        for table in tables {
            for row in table.rows {
                lines.append([
                    table.id,
                    ProfileV3TransformGrouping.encode(row.groupPath),
                    row.from,
                    row.to
                ].map(quote).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Parses and validates without mutating anything; apply is a separate,
    /// atomic document operation.
    public static func parse(_ text: String) throws -> [ProfileV3TransformTableRows] {
        let records = try records(text)
        guard let first = records.first, first == header else {
            throw ProfileAuthoringError.invalidJSON("CSVの先頭行は table,groupPath,from,to にしてください")
        }
        var order: [String] = []
        var rows: [String: [ProfileV3TransformRow]] = [:]
        var seen: [String: Set<String>] = [:]
        for (index, record) in records.dropFirst().enumerated() {
            if record == [""] { continue }
            guard record.count == 4 else {
                throw ProfileAuthoringError.invalidJSON("CSV \(index + 2)行目: 列は4つ必要です")
            }
            let table = record[0]
            try ProfileDocument.v3ValidateSemanticID(table, field: "table")
            let path = ProfileV3TransformGrouping.decode(record[1])
            try ProfileV3TransformGrouping.validate(groupPath: path)
            guard !record[2].isEmpty else {
                throw ProfileAuthoringError.invalidJSON("CSV \(index + 2)行目: 変換前が空です")
            }
            guard seen[table, default: []].insert(record[2]).inserted else {
                throw ProfileAuthoringError.invalidJSON(
                    "CSV \(index + 2)行目: 表 \(table) で変換前「\(record[2])」が重複しています"
                )
            }
            if rows[table] == nil { order.append(table) }
            rows[table, default: []].append(
                ProfileV3TransformRow(from: record[2], to: record[3], groupPath: path)
            )
        }
        return order.map { ProfileV3TransformTableRows(id: $0, rows: rows[$0] ?? []) }
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
        // Strip a UTF-8 BOM some spreadsheet apps add.
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
                return ProfileV3TransformRow(from: from, to: to, groupPath: path)
            }
            return ProfileV3TransformTableRows(id: id, rows: rows)
        }
    }

    /// Replaces one table's rows (creating the table if needed). Unknown
    /// entry fields are preserved for rows whose `from` survives.
    public mutating func v3SetTransformTableRows(_ table: ProfileV3TransformTableRows) throws {
        try Self.v3ValidateSemanticID(table.id, field: "transformTable.id")
        guard table.rows.count <= 2048 else {
            throw ProfileAuthoringError.invalidJSON("変換表は2048行までです")
        }
        var seen = Set<String>()
        for row in table.rows {
            guard !row.from.isEmpty else {
                throw ProfileAuthoringError.invalidJSON("変換前が空の行があります")
            }
            guard seen.insert(row.from).inserted else {
                throw ProfileAuthoringError.invalidJSON("変換前「\(row.from)」が重複しています")
            }
            try ProfileV3TransformGrouping.validate(groupPath: row.groupPath)
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
        object["entries"] = .array(table.rows.map { row in
            var item = previous[row.from] ?? [:]
            item["from"] = .string(row.from)
            item["to"] = .string(row.to)
            if row.groupPath.isEmpty {
                item.removeValue(forKey: "groupPath")
            } else {
                item["groupPath"] = .array(row.groupPath.map(JSONNode.string))
            }
            return .object(item)
        })
        if let index {
            tables[index] = .object(object)
        } else {
            tables.append(.object(object))
        }
        top["transformTables"] = .array(tables)
        root = .object(top)
    }

    /// Applies a parsed CSV atomically: every listed table is replaced; tables
    /// absent from the CSV are untouched.
    public mutating func v3ApplyTransformCSV(_ tables: [ProfileV3TransformTableRows]) throws {
        var candidate = self
        for table in tables {
            try candidate.v3SetTransformTableRows(table)
        }
        self = candidate
    }
}
