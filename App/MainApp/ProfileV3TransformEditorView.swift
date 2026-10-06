import SwiftUI
import UniformTypeIdentifiers
import GestureIMEProfileAuthoring

/// #157 U5: dense ordinary Transform authoring. Semantic grouping/search/CSV/
/// draft/reverse behavior stays owned by the existing authoring engine; this
/// view applies the P13 title-first, no-internal-ID presentation contract.
struct ProfileV3TransformEditorView: View {
    @ObservedObject var editor: ProfileV3EditorModel
    let focusedTableID: String?

    init(
        editor: ProfileV3EditorModel,
        focusedTableID: String? = nil
    ) {
        _editor = ObservedObject(wrappedValue: editor)
        self.focusedTableID = focusedTableID
    }

    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var importing = false
    @State private var drafts: [String: [ProfileV3TransformRow]] = [:]
    /// Incomplete or validation-rejected edits of persisted rows. These are
    /// editor-only until a valid replacement commits successfully.
    @State private var pendingEdits: [String: [UUID: ProfileV3TransformRow]] = [:]
    @State private var renaming: RenameTarget?
    @State private var renameText = ""

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
        let mapped = editor.transformRows.map { table in
            var copy = table
            if let edits = pendingEdits[table.id] {
                copy.rows = copy.rows.map { edits[$0.editorID] ?? $0 }
            }
            copy.rows += drafts[table.id] ?? []
            return copy
        }
        guard let focusedTableID,
              let focused = mapped.first(where: { $0.id == focusedTableID }) else {
            return mapped
        }
        return [focused] + mapped.filter { $0.id != focusedTableID }
    }

    var body: some View {
        let current = tables
        let tree = ProfileV3TransformGrouping.tree(current)
        let search = ProfileV3TransformGrouping.search(query, in: tree)
        List {
            if current.isEmpty {
                ContentUnavailableView {
                    Label("変換表はありません", systemImage: "character.textbox")
                } description: {
                    Text("変換前と変換後の文字を対応づける表を追加できます。")
                }
            }

            ForEach(current.indices, id: \.self) { index in
                let table = current[index]
                let node = tree[index]
                Section {
                    tableHeader(
                        table,
                        fallbackPosition: index
                    )
                    ForEach(node.children) { child in
                        nodeView(
                            child,
                            table: table,
                            search: search
                        )
                    }
                    addRowButton(
                        table: table,
                        path: []
                    )
                }
            }
        }
        .searchable(
            text: $query,
            prompt: "変換前・変換後・グループを検索"
        )
        .navigationTitle("文字変換表")
        .toolbar {
            ToolbarItemGroup(
                placement: .topBarTrailing
            ) {
                Button {
                    addTable()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("変換表を追加")

                Menu {
                    if let url =
                            editor.exportTransformCSV() {
                        ShareLink(item: url) {
                            Label(
                                "CSVを書き出し",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                    }

                    Button {
                        importing = true
                    } label: {
                        Label(
                            "CSVを読み込み",
                            systemImage: "square.and.arrow.down"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("その他の操作")
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
            isPresented: Binding(
                get: { renaming != nil },
                set: {
                    if !$0 { renaming = nil }
                }
            )
        ) {
            TextField("名前", text: $renameText)
            Button("キャンセル", role: .cancel) {
                renaming = nil
            }
            Button("OK") {
                applyRename()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = editor.errorMessage {
                VStack(spacing: 0) {
                    ProfileV3InlineAuthoringError(
                        message: message,
                        correctionHint:
                            "入力内容は残っています。衝突や未入力を修正して、もう一度確定してください。"
                    )

                    Button("閉じる") {
                        editor.errorMessage = nil
                    }
                    .font(.caption)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 44
                    )
                    .background(.thinMaterial)
                }
            }
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

    // MARK: Table identity + table-wide controls

    @ViewBuilder
    private func tableHeader(
        _ table: ProfileV3TransformTableRows,
        fallbackPosition: Int
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                renameText = table.title ?? ""
                renaming = RenameTarget(
                    tableID: table.id,
                    kind: .tableTitle
                )
            } label: {
                HStack(spacing: 6) {
                    Text(
                        ordinaryTitle(
                            table,
                            fallbackPosition:
                                fallbackPosition
                        )
                    )
                    .font(.headline)
                    .foregroundStyle(.primary)

                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("タイトルを変更")

            Spacer(minLength: 8)

            Menu {
                Button("グループを追加") {
                    renameText = ""
                    renaming = RenameTarget(
                        tableID: table.id,
                        kind: .newGroup([])
                    )
                }
            } label: {
                Image(systemName: "folder.badge.plus")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("グループを追加")
        }

        Toggle(
            "表全体を逆向きにも変換",
            isOn: Binding(
                get: { table.reverseAll },
                set: { on in
                    var updated =
                        persisted(table.id) ?? table
                    updated.reverseAll = on
                    _ = editor.setTransformTable(updated)
                }
            )
        )
        .frame(minHeight: 44)
    }

    private func ordinaryTitle(
        _ table: ProfileV3TransformTableRows,
        fallbackPosition: Int
    ) -> String {
        let position =
            editor.transformRows.firstIndex(where: {
                $0.id == table.id
            })
            ?? fallbackPosition
        return table.ordinaryTitle(
            position: position
        )
    }

    private func addTable() {
        do {
            let id = try editor.newTransformTableID()
            _ = editor.setTransformTable(
                ProfileV3TransformTableRows(
                    id: id,
                    title: "新しい変換表",
                    rows: []
                )
            )
        } catch {
            editor.errorMessage = error.localizedDescription
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
                ProfileV3HierarchyRow(depth: max(0, path.count - 1)) {
                    HStack {
                        Label(name, systemImage: "folder")
                        Spacer()
                        Menu {
                        profileV3MoveMenuItems(
                            canMoveUp: (persisted(table.id) ?? table)
                                .canReorderGroup(path, by: -1),
                            canMoveDown: (persisted(table.id) ?? table)
                                .canReorderGroup(path, by: 1),
                            onMoveUp: {
                                reorderGroup(path, by: -1, in: table)
                            },
                            onMoveDown: {
                                reorderGroup(path, by: 1, in: table)
                            }
                        )
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
                            Image(systemName: "ellipsis.circle")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("グループの操作")
                    }
                }
            })
        case .leaf(let row):
            return AnyView(
                ProfileV3HierarchyRow(
                    depth: row.groupPath.count
                ) {
                    ProfileV3TransformRowEditor(
                        row: row,
                        reverseAll: table.reverseAll,
                        highlighted:
                            search.matches.contains(
                                node.id
                            ),
                        groups: table.groups,
                        onCommit: { updated in
                            commit(updated, in: table)
                        },
                        onDelete: {
                            delete(row, in: table)
                        },
                        onMove: { path in
                            move(
                                row,
                                to: path,
                                in: table
                            )
                        }
                    )
                }
                .swipeActions(
                    edge: .trailing,
                    allowsFullSwipe: false
                ) {
                    Button(role: .destructive) {
                        delete(row, in: table)
                    } label: {
                        Label(
                            "削除",
                            systemImage: "trash"
                        )
                    }
                }
            )
        case .table:
            return AnyView(EmptyView())
        }
    }

    private func groupPath(of nodeID: String, tableID: String) -> [String] {
        ProfileV3TransformGrouping.decode(String(nodeID.dropFirst(tableID.count + 1)))
    }

    private func isOpen(
        _ id: String,
        search: (expanded: Set<String>, matches: Set<String>)
    ) -> Binding<Bool> {
        Binding(
            get: {
                expanded.contains(id)
                    || search.expanded.contains(id)
            },
            set: { open in
                // Search expansion is temporary presentation state. Do not
                // overwrite the user's persistent disclosure choices while a
                // query is forcing ancestors open.
                guard query
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty else {
                    return
                }

                if open {
                    expanded.insert(id)
                } else {
                    expanded.remove(id)
                }
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

        if persistedTable.rows.contains(where: { $0.editorID == row.editorID }) {
            // Existing semantic rows never disappear merely because the user
            // temporarily clears one side. Keep incomplete/rejected edits local.
            guard let candidate = ProfileV3TransformEditPolicy.persistenceCandidate(
                for: row,
                in: persistedTable
            ) else {
                pendingEdits[table.id, default: [:]][row.editorID] = row
                return
            }
            if editor.setTransformTable(candidate) {
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
        guard let candidate = ProfileV3TransformEditPolicy.persistenceCandidate(
            for: row,
            in: persistedTable
        ) else { return }

        if editor.setTransformTable(candidate) {
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
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            if highlighted {
                Label(
                    "検索結果",
                    systemImage: "magnifyingglass"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                inlineRow
                stackedRow
            }
        }
        .textFieldStyle(.roundedBorder)
        .listRowBackground(
            highlighted
                ? Color.secondary.opacity(0.08)
                : nil
        )
        .onAppear(perform: sync)
        .onChange(of: row) { _, _ in
            sync()
        }
    }

    private var inlineRow: some View {
        HStack(spacing: 6) {
            mappingFields(
                minimumFieldWidth: 88
            )
            reverseControl
            rowMenu
        }
    }

    private var stackedRow: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                mappingFields(
                    minimumFieldWidth: 0
                )
            }

            HStack(spacing: 8) {
                reverseControl
                Spacer(minLength: 8)
                rowMenu
            }
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private func mappingFields(
        minimumFieldWidth: CGFloat
    ) -> some View {
        TextField("変換前", text: $from)
            .frame(
                minWidth: minimumFieldWidth,
                maxWidth: .infinity
            )
            .onSubmit(commit)

        Image(
            systemName:
                reverseAll || row.reverse
                ? "arrow.left.arrow.right"
                : "arrow.right"
        )
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

        TextField("変換後", text: $to)
            .frame(
                minWidth: minimumFieldWidth,
                maxWidth: .infinity
            )
            .onSubmit(commit)
    }

    @ViewBuilder
    private var reverseControl: some View {
        if reverseAll {
            HStack(spacing: 4) {
                Toggle(
                    "逆",
                    isOn: .constant(true)
                )
                .toggleStyle(.button)
                .disabled(true)

                Text("表全体で有効")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "逆向きにも変換。表全体の設定で有効"
            )
        } else {
            Toggle(
                "逆",
                isOn: Binding(
                    get: { row.reverse },
                    set: { on in
                        var updated = row
                        updated.reverse = on
                        onCommit(updated)
                    }
                )
            )
            .toggleStyle(.button)
            .disabled(row.isDraft)
            .frame(minHeight: 44)
            .accessibilityLabel(
                "逆向きにも変換"
            )
            .accessibilityValue(
                row.reverse ? "オン" : "オフ"
            )
        }
    }

    private var rowMenu: some View {
        Menu {
            Button("グループなしへ移動") {
                onMove([])
            }

            ForEach(groups, id: \.self) { path in
                Button(
                    path.joined(
                        separator: " › "
                    )
                    + " へ移動"
                ) {
                    onMove(path)
                }
            }

            Divider()

            Button(
                "削除",
                role: .destructive,
                action: onDelete
            )
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("行の操作")
    }

    private func sync() {
        from = row.from
        to = row.to
    }

    private func commit() {
        onCommit(
            ProfileV3TransformRow(
                from: from,
                to: to,
                groupPath: row.groupPath,
                reverse: row.reverse,
                editorID: row.editorID
            )
        )
    }
}
