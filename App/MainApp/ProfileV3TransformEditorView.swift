import SwiftUI
import UniformTypeIdentifiers
import GestureIMEProfileAuthoring

/// #101 / frozen #95 §F6: Transform authoring v2. Ordinary UI shows table
/// titles (internal IDs only under 詳細), real group nodes (no path text),
/// reverse checkboxes and transient blank draft rows. Disclosure/search and
/// drafts are view-local; only valid rows reach the Profile.
struct ProfileV3TransformEditorView: View {
    @ObservedObject var editor: ProfileV3EditorModel

    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var importing = false
    @State private var drafts: [String: [ProfileV3TransformRow]] = [:]
    /// Incomplete or validation-rejected edits of persisted rows. These are
    /// editor-only until a valid replacement commits successfully.
    @State private var pendingEdits: [String: [UUID: ProfileV3TransformRow]] = [:]
    @State private var renaming: RenameTarget?
    @State private var renameText = ""
    @State private var showAdvanced = false

    private struct RenameTarget: Identifiable {
        enum Kind { case tableTitle, group([String]), newGroup([String]) }
        let tableID: String
        let kind: Kind
        var id: String {
            switch kind {
            case .tableTitle: "t:" + tableID
            case .group(let p): "g:" + tableID + "/" + p.joined(separator: "/")
            case .newGroup(let p): "n:" + tableID + "/" + p.joined(separator: "/")
            }
        }
    }

    /// Persisted tables merged with this view's transient draft rows.
    private var tables: [ProfileV3TransformTableRows] {
        editor.transformRows.map { table in
            var copy = table
            if let edits = pendingEdits[table.id] {
                copy.rows = copy.rows.map { edits[$0.editorID] ?? $0 }
            }
            copy.rows += drafts[table.id] ?? []
            return copy
        }
    }

    var body: some View {
        let current = tables
        let tree = ProfileV3TransformGrouping.tree(current)
        let search = ProfileV3TransformGrouping.search(query, in: tree)
        List {
            ForEach(current.indices, id: \.self) { index in
                let table = current[index]
                let node = tree[index]
                Section {
                    tableHeader(table)
                    ForEach(node.children) { child in
                        nodeView(child, table: table, search: search)
                    }
                    addRowButton(table: table, path: [])
                } header: {
                    Text(table.displayTitle)
                }
            }
            Section {
                Button {
                    if let id = try? editor.newTransformTableID() {
                        editor.setTransformTable(ProfileV3TransformTableRows(id: id, title: "新しい変換表", rows: []))
                    }
                } label: {
                    Label("変換表を追加", systemImage: "plus.rectangle.on.rectangle")
                }
                Toggle("内部IDを表示（詳細設定）", isOn: $showAdvanced)
            } footer: {
                Text("グループは編集用の整理です。変換の結果は変わりません。")
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
        .alert(
            renameTitle,
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("名前", text: $renameText)
            Button("キャンセル", role: .cancel) { renaming = nil }
            Button("OK") { applyRename() }
        }
    }

    private var renameTitle: String {
        switch renaming?.kind {
        case .tableTitle: "表のタイトル"
        case .group: "グループ名を変更"
        case .newGroup: "グループを追加"
        case nil: ""
        }
    }

    // MARK: Table header (title, reverseAll, advanced ID)

    @ViewBuilder
    private func tableHeader(_ table: ProfileV3TransformTableRows) -> some View {
        HStack {
            Button {
                renameText = table.title ?? ""
                renaming = RenameTarget(tableID: table.id, kind: .tableTitle)
            } label: {
                Label("タイトルを変更", systemImage: "pencil")
            }
            .buttonStyle(.borderless)
            Spacer()
            Menu {
                Button("グループを追加") {
                    renameText = ""
                    renaming = RenameTarget(tableID: table.id, kind: .newGroup([]))
                }
            } label: {
                Image(systemName: "folder.badge.plus").frame(width: 44, height: 44)
            }
            .accessibilityLabel("グループを追加")
        }
        Toggle(
            "すべての行を逆向きにも変換",
            isOn: Binding(
                get: { table.reverseAll },
                set: { on in
                    var updated = persisted(table.id) ?? table
                    updated.reverseAll = on
                    editor.setTransformTable(updated)
                }
            )
        )
        if showAdvanced {
            LabeledContent(ProfileV3DisplayCatalog.title(.advancedInternalID)) {
                Text(table.id).font(.caption.monospaced())
            }
        }
    }

    // MARK: Nodes

    private func nodeView(
        _ node: ProfileV3TransformNode,
        table: ProfileV3TransformTableRows,
        search: (expanded: Set<String>, matches: Set<String>)
    ) -> AnyView {
        switch node.kind {
        case .group(let name):
            let path = groupPath(of: node.id, tableID: table.id)
            return AnyView(DisclosureGroup(isExpanded: isOpen(node.id, search: search)) {
                ForEach(node.children) { child in
                    nodeView(child, table: table, search: search)
                }
                addRowButton(table: table, path: path)
            } label: {
                HStack {
                    Label(name, systemImage: "folder")
                    Spacer()
                    Menu {
                        Button("上へ") {
                            reorderGroup(path, by: -1, in: table)
                        }
                        .disabled(!(persisted(table.id) ?? table).canReorderGroup(path, by: -1))
                        Button("下へ") {
                            reorderGroup(path, by: 1, in: table)
                        }
                        .disabled(!(persisted(table.id) ?? table).canReorderGroup(path, by: 1))
                        Menu("移動") {
                            Button("最上位へ") {
                                moveGroup(path, to: [], in: table)
                            }
                            ForEach(
                                table.groups.filter { destination in
                                    destination != path && !destination.starts(with: path)
                                },
                                id: \.self
                            ) { destination in
                                Button(destination.joined(separator: " › ") + " の中へ") {
                                    moveGroup(path, to: destination, in: table)
                                }
                            }
                        }
                        Button("名前を変更") {
                            renameText = name
                            renaming = RenameTarget(tableID: table.id, kind: .group(path))
                        }
                        Button("中にグループを追加") {
                            renameText = ""
                            renaming = RenameTarget(tableID: table.id, kind: .newGroup(path))
                        }
                        Button("グループを削除（中身は上の階層へ）", role: .destructive) {
                            var updated = persisted(table.id) ?? table
                            updated.deleteGroup(path)
                            rewriteTransientRows(tableID: table.id) { p in
                                p.starts(with: path) ? Array(path.dropLast()) + p.dropFirst(path.count) : p
                            }
                            editor.setTransformTable(updated)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("グループの操作")
                }
            })
        case .leaf(let row):
            return AnyView(ProfileV3TransformRowEditor(
                row: row,
                reverseAll: table.reverseAll,
                highlighted: search.matches.contains(node.id),
                groups: table.groups,
                onCommit: { updated in commit(updated, in: table) },
                onDelete: { delete(row, in: table) },
                onMove: { path in move(row, to: path, in: table) }
            ))
        case .table:
            return AnyView(EmptyView())
        }
    }

    private func groupPath(of nodeID: String, tableID: String) -> [String] {
        ProfileV3TransformGrouping.decode(String(nodeID.dropFirst(tableID.count + 1)))
    }

    private func isOpen(_ id: String, search: (expanded: Set<String>, matches: Set<String>)) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) || search.expanded.contains(id) },
            set: { open in
                if open { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    private func addRowButton(table: ProfileV3TransformTableRows, path: [String]) -> some View {
        Button {
            // §F6.5: blank transient draft with grey placeholders.
            drafts[table.id, default: []].append(ProfileV3TransformRow(from: "", to: "", groupPath: path))
        } label: {
            Label("行を追加", systemImage: "plus")
        }
        .font(.caption)
    }

    // MARK: Mutations

    private func persisted(_ tableID: String) -> ProfileV3TransformTableRows? {
        editor.transformRows.first { $0.id == tableID }
    }

    private func commit(_ row: ProfileV3TransformRow, in table: ProfileV3TransformTableRows) {
        guard var persistedTable = persisted(table.id) else { return }

        if let index = persistedTable.rows.firstIndex(where: { $0.editorID == row.editorID }) {
            // Existing semantic rows never disappear merely because the user
            // temporarily clears one side. Keep incomplete/rejected edits local.
            if row.isDraft {
                pendingEdits[table.id, default: [:]][row.editorID] = row
                return
            }
            persistedTable.rows[index] = row
            if editor.setTransformTable(persistedTable) {
                pendingEdits[table.id]?[row.editorID] = nil
            } else {
                pendingEdits[table.id, default: [:]][row.editorID] = row
            }
            return
        }

        // New rows live in the transient draft collection until persistence
        // and whole-document validation both succeed.
        if let draftIndex = drafts[table.id]?.firstIndex(where: { $0.editorID == row.editorID }) {
            drafts[table.id]?[draftIndex] = row
        } else {
            drafts[table.id, default: []].append(row)
        }
        guard !row.isDraft else { return }

        persistedTable.rows.append(row)
        if editor.setTransformTable(persistedTable) {
            drafts[table.id]?.removeAll { $0.editorID == row.editorID }
        }
    }

    private func delete(_ row: ProfileV3TransformRow, in table: ProfileV3TransformTableRows) {
        if drafts[table.id]?.contains(where: { $0.editorID == row.editorID }) == true {
            drafts[table.id]?.removeAll { $0.editorID == row.editorID }
            return
        }
        guard var updated = persisted(table.id) else { return }
        updated.rows.removeAll { $0.editorID == row.editorID }
        if editor.setTransformTable(updated) {
            pendingEdits[table.id]?[row.editorID] = nil
        }
    }

    private func move(_ row: ProfileV3TransformRow, to path: [String], in table: ProfileV3TransformTableRows) {
        if let index = drafts[table.id]?.firstIndex(where: { $0.editorID == row.editorID }) {
            drafts[table.id]?[index].groupPath = path
            return
        }
        if var pending = pendingEdits[table.id]?[row.editorID] {
            pending.groupPath = path
            pendingEdits[table.id]?[row.editorID] = pending
            return
        }
        guard var updated = persisted(table.id) else { return }
        updated.moveRow(editorID: row.editorID, to: path)
        editor.setTransformTable(updated)
    }

    private func reorderGroup(_ path: [String], by offset: Int, in table: ProfileV3TransformTableRows) {
        guard var updated = persisted(table.id),
              updated.reorderGroup(path, by: offset) else { return }
        editor.setTransformTable(updated)
    }

    private func moveGroup(_ path: [String], to parent: [String], in table: ProfileV3TransformTableRows) {
        guard var updated = persisted(table.id) else { return }
        let name = path.last ?? ""
        let destination = parent + [name]
        do {
            try updated.moveGroup(path, to: parent)
            rewriteTransientRows(tableID: table.id) { p in
                p.starts(with: path) ? destination + p.dropFirst(path.count) : p
            }
            editor.setTransformTable(updated)
        } catch {
            editor.errorMessage = error.localizedDescription
        }
    }

    private func rewriteTransientRows(tableID: String, _ transform: ([String]) -> [String]) {
        if var rows = drafts[tableID] {
            for index in rows.indices { rows[index].groupPath = transform(rows[index].groupPath) }
            drafts[tableID] = rows
        }
        if var edits = pendingEdits[tableID] {
            for (id, var row) in edits {
                row.groupPath = transform(row.groupPath)
                edits[id] = row
            }
            pendingEdits[tableID] = edits
        }
    }

    private func applyRename() {
        guard let target = renaming, var updated = persisted(target.tableID) else { return }
        let text = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        do {
            switch target.kind {
            case .tableTitle:
                updated.title = text.isEmpty ? nil : text
            case .group(let path):
                try updated.renameGroup(path, to: text)
                let renamed = Array(path.dropLast()) + [text]
                rewriteTransientRows(tableID: target.tableID) { p in
                    p.starts(with: path) ? renamed + p.dropFirst(path.count) : p
                }
            case .newGroup(let parent):
                try updated.addGroup(named: text, under: parent)
            }
            editor.setTransformTable(updated)
        } catch {
            editor.errorMessage = error.localizedDescription
        }
    }
}

private struct ProfileV3TransformRowEditor: View {
    let row: ProfileV3TransformRow
    let reverseAll: Bool
    let highlighted: Bool
    let groups: [[String]]
    let onCommit: (ProfileV3TransformRow) -> Void
    let onDelete: () -> Void
    let onMove: ([String]) -> Void

    @State private var from = ""
    @State private var to = ""

    var body: some View {
        HStack(spacing: 6) {
            TextField("変換前", text: $from)
                .frame(minWidth: 0, maxWidth: .infinity)
                .onSubmit(commit)
            Image(systemName: reverseAll || row.reverse ? "arrow.left.arrow.right" : "arrow.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("変換後", text: $to)
                .frame(minWidth: 0, maxWidth: .infinity)
                .onSubmit(commit)
            // Row reverse: shown checked and disabled when the table reverses all.
            Toggle(
                "逆",
                isOn: Binding(
                    get: { reverseAll || row.reverse },
                    set: { on in
                        var updated = row
                        updated.reverse = on
                        onCommit(updated)
                    }
                )
            )
            .toggleStyle(.button)
            .disabled(reverseAll || row.isDraft)
            .accessibilityLabel("逆向きにも変換")
            Menu {
                Button("グループなしへ移動") { onMove([]) }
                ForEach(groups, id: \.self) { path in
                    Button(path.joined(separator: " › ") + " へ移動") { onMove(path) }
                }
                Divider()
                Button("削除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis").frame(width: 32, height: 44)
            }
            .accessibilityLabel("行の操作")
        }
        .textFieldStyle(.roundedBorder)
        .listRowBackground(highlighted ? Color.yellow.opacity(0.2) : nil)
        .onAppear(perform: sync)
        .onChange(of: row) { _, _ in sync() }
    }

    private func sync() {
        from = row.from
        to = row.to
    }

    private func commit() {
        onCommit(ProfileV3TransformRow(
            from: from,
            to: to,
            groupPath: row.groupPath,
            reverse: row.reverse,
            editorID: row.editorID
        ))
    }
}
