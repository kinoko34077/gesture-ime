import SwiftUI
import UniformTypeIdentifiers
import GestureIMEProfileAuthoring

/// #79 / #69 §11: Notion-like disclosure editing for TransformTables. Open /
/// closed state is view-local and never persisted; edits write flat rows +
/// `groupPath` metadata through the shared validated document path.
struct ProfileV3TransformEditorView: View {
    @ObservedObject var editor: ProfileV3EditorModel

    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var importing = false
    @State private var newTableID = ""

    private var tables: [ProfileV3TransformTableRows] { editor.transformRows }

    var body: some View {
        let tree = ProfileV3TransformGrouping.tree(tables)
        let search = ProfileV3TransformGrouping.search(query, in: tree)
        List {
            Section {
                ForEach(tree) { node in
                    nodeView(node, search: search)
                }
            } footer: {
                Text("グループは編集用の整理です。変換の結果は変わりません。")
            }

            Section("表を追加") {
                HStack {
                    TextField("内部ID（例: my.table）", text: $newTableID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("追加") {
                        editor.setTransformTable(ProfileV3TransformTableRows(id: newTableID, rows: []))
                        newTableID = ""
                    }
                    .disabled(newTableID.isEmpty)
                }
            }
        }
        .searchable(text: $query, prompt: "変換前・変換後・グループを検索")
        .navigationTitle("文字変換表")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let url = editor.exportTransformCSV() {
                    ShareLink(item: url) {
                        Label("CSVを書き出し", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    importing = true
                } label: {
                    Label("CSVを読み込み", systemImage: "square.and.arrow.down")
                }
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                editor.applyTransformCSV(text)
            } else {
                editor.errorMessage = "CSVはUTF-8で保存してください"
            }
        }
    }

    private func isOpen(_ id: String, search: (expanded: Set<String>, matches: Set<String>)) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) || search.expanded.contains(id) },
            set: { open in
                if open { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    private func nodeView(
        _ node: ProfileV3TransformNode,
        search: (expanded: Set<String>, matches: Set<String>)
    ) -> AnyView {
        switch node.kind {
        case .table(let id), .group(let id):
            let isTable: Bool = if case .table = node.kind { true } else { false }
            return AnyView(DisclosureGroup(isExpanded: isOpen(node.id, search: search)) {
                ForEach(node.children) { child in
                    nodeView(child, search: search)
                }
                Button {
                    addRow(under: node)
                } label: {
                    Label("行を追加", systemImage: "plus")
                }
                .font(.caption)
            } label: {
                Label(id, systemImage: isTable ? "tablecells" : "folder")
                    .font(isTable ? .headline : .subheadline)
            })
        case .leaf(let row):
            return AnyView(ProfileV3TransformRowEditor(
                row: row,
                highlighted: search.matches.contains(node.id)
            ) { updated in
                replace(row, with: updated, nodeID: node.id)
            } onDelete: {
                replace(row, with: nil, nodeID: node.id)
            })
        }
    }

    private func tableID(of nodeID: String) -> String? {
        tables.map(\.id).filter { nodeID == $0 || nodeID.hasPrefix($0 + "/") }.max { $0.count < $1.count }
    }

    private func addRow(under node: ProfileV3TransformNode) {
        guard let tableID = tableID(of: node.id),
              var table = tables.first(where: { $0.id == tableID }) else { return }
        let path = ProfileV3TransformGrouping.decode(
            String(node.id.dropFirst(tableID.count).drop { $0 == "/" })
        )
        var from = "新しい文字"
        var index = 2
        while table.rows.contains(where: { $0.from == from }) {
            from = "新しい文字\(index)"
            index += 1
        }
        table.rows.append(ProfileV3TransformRow(from: from, to: from, groupPath: path))
        editor.setTransformTable(table)
        expanded.insert(node.id)
    }

    private func replace(_ row: ProfileV3TransformRow, with updated: ProfileV3TransformRow?, nodeID: String) {
        guard let tableID = tableID(of: nodeID),
              var table = tables.first(where: { $0.id == tableID }),
              let index = table.rows.firstIndex(where: { $0.from == row.from }) else { return }
        if let updated {
            table.rows[index] = updated
        } else {
            table.rows.remove(at: index)
        }
        editor.setTransformTable(table)
    }
}

private struct ProfileV3TransformRowEditor: View {
    let row: ProfileV3TransformRow
    let highlighted: Bool
    let onCommit: (ProfileV3TransformRow) -> Void
    let onDelete: () -> Void

    @State private var from = ""
    @State private var to = ""
    @State private var group = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("変換前", text: $from)
                    .onSubmit(commit)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("変換後", text: $to)
                    .onSubmit(commit)
            }
            .textFieldStyle(.roundedBorder)
            TextField("グループ（「/」区切り、空欄でグループなし）", text: $group)
                .font(.caption)
                .onSubmit(commit)
        }
        .listRowBackground(highlighted ? Color.yellow.opacity(0.2) : nil)
        .swipeActions {
            Button("削除", role: .destructive, action: onDelete)
        }
        .onAppear(perform: sync)
        .onChange(of: row) { _, _ in sync() }
    }

    private func sync() {
        from = row.from
        to = row.to
        group = ProfileV3TransformGrouping.encode(row.groupPath)
    }

    private func commit() {
        onCommit(ProfileV3TransformRow(
            from: from,
            to: to,
            groupPath: ProfileV3TransformGrouping.decode(group)
        ))
    }
}
