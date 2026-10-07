import SwiftUI
import UniformTypeIdentifiers
import GestureIMEProfileAuthoring

struct ProductTransformList: View {
    @ObservedObject var editor: ProfileV3EditorModel

    @State private var creating = false
    @State private var importing = false
    @State private var deletingID: String?

    var body: some View {
        List {
            if editor.transformRows.isEmpty {
                ContentUnavailableView(
                    "文字変換はありません",
                    systemImage: "character.textbox"
                )
            } else {
                ForEach(Array(editor.transformRows.enumerated()), id: \.element.id) { index, table in
                    NavigationLink {
                        ProductTransformDetail(
                            editor: editor,
                            tableID: table.id
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(table.ordinaryTitle(position: index))
                            Text("\(table.persistableRows.count)行")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deletingID = table.id
                        } label: {
                            Label("削除", systemImage: "trash")
                        }

                        Button {
                            _ = editor.duplicateTransformTable(id: table.id)
                        } label: {
                            Label("複製", systemImage: "plus.square.on.square")
                        }
                    }
                }
            }
        }
        .navigationTitle("文字変換")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    importing = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("CSVを読み込む")

                if let url = editor.exportTransformCSV() {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("CSVを書き出す")
                }

                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("変換表を追加")
            }
        }
        .sheet(isPresented: $creating) {
            ProductTextEditSheet(
                title: "変換表を追加",
                label: "名前",
                initialValue: ""
            ) { title in
                _ = editor.createTransformTable(title: title)
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let data = try Data(contentsOf: url)
                    guard let text = String(data: data, encoding: .utf8) else {
                        throw CocoaError(.fileReadInapplicableStringEncoding)
                    }
                    editor.applyTransformCSV(text)
                } catch {
                    editor.errorMessage = error.localizedDescription
                }
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    editor.errorMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog(
            "変換表を削除しますか？",
            isPresented: Binding(
                get: { deletingID != nil },
                set: { if !$0 { deletingID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let deletingID {
                    _ = editor.deleteTransformTable(id: deletingID)
                }
                deletingID = nil
            }
            Button("キャンセル", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) {
            if let message = editor.errorMessage {
                ProductInlineError(message: message) {
                    editor.errorMessage = nil
                }
            }
        }
    }
}

private struct ProductTransformDetail: View {
    @ObservedObject var editor: ProfileV3EditorModel
    let tableID: String

    @State private var draft: ProfileV3TransformTableRows?
    @State private var persistedBaseline: ProfileV3TransformTableRows?
    @State private var searchText = ""
    @State private var addingGroup = false
    @State private var renamingGroup: [String]?
    @State private var localError: String?

    var body: some View {
        List {
            if let draft {
                Section("変換表") {
                    TextField(
                        "名前",
                        text: Binding(
                            get: { draft.title ?? "" },
                            set: { value in
                                updateDraft { $0.title = value }
                            }
                        )
                    )
                    Toggle(
                        "表全体を逆変換にも使う",
                        isOn: Binding(
                            get: { draft.reverseAll },
                            set: { value in
                                updateDraft { $0.reverseAll = value }
                            }
                        )
                    )
                }

                Section("グループ") {
                    if draft.groups.isEmpty {
                        Text("グループなし")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(draft.groups, id: \.self) { path in
                        HStack {
                            Text(String(repeating: "　", count: max(0, path.count - 1)) + (path.last ?? ""))
                            Spacer()
                            Menu {
                                Button("名前を変更") {
                                    renamingGroup = path
                                }
                                Button("上へ") {
                                    updateDraft {
                                        _ = $0.reorderGroup(path, by: -1)
                                    }
                                }
                                .disabled(!draft.canReorderGroup(path, by: -1))
                                Button("下へ") {
                                    updateDraft {
                                        _ = $0.reorderGroup(path, by: 1)
                                    }
                                }
                                .disabled(!draft.canReorderGroup(path, by: 1))
                                Button("削除", role: .destructive) {
                                    updateDraft {
                                        $0.deleteGroup(path)
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .frame(width: 44, height: 44)
                            }
                        }
                    }

                    Button {
                        addingGroup = true
                    } label: {
                        Label("グループを追加", systemImage: "plus")
                    }
                }

                Section("変換行") {
                    if draft.rows.isEmpty {
                        Text("変換行なし")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(draft.rows.indices, id: \.self) { index in
                        ProductTransformRowEditor(
                            row: Binding(
                                get: { currentDraft.rows[index] },
                                set: { row in
                                    updateDraft { $0.rows[index] = row }
                                }
                            ),
                            groups: draft.groups,
                            highlighted: rowMatchesSearch(draft.rows[index])
                        )
                        .frame(minHeight: 52)
                    }
                    .onMove { source, destination in
                        updateDraft {
                            $0.rows.move(
                                fromOffsets: source,
                                toOffset: destination
                            )
                        }
                    }
                    .onDelete { offsets in
                        updateDraft {
                            $0.rows.remove(atOffsets: offsets)
                        }
                    }

                    Button {
                        updateDraft {
                            $0.rows.append(
                                ProfileV3TransformRow(
                                    from: "",
                                    to: ""
                                )
                            )
                        }
                    } label: {
                        Label("変換行を追加", systemImage: "plus")
                    }
                }
            }
        }
        .navigationTitle(ordinaryTitle)
        .searchable(text: $searchText, prompt: "変換前・変換後を検索")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Button("適用") {
                    apply()
                }
            }
        }
        .onAppear {
            if draft == nil {
                let current = editor.transformRows.first {
                    $0.id == tableID
                }
                draft = current
                persistedBaseline = current
            }
        }
        .sheet(isPresented: $addingGroup) {
            ProductTextEditSheet(
                title: "グループを追加",
                label: "グループ名",
                initialValue: ""
            ) { name in
                do {
                    try updateDraftThrowing {
                        try $0.addGroup(named: name)
                    }
                } catch {
                    localError = error.localizedDescription
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { renamingGroup != nil },
                set: { if !$0 { renamingGroup = nil } }
            )
        ) {
            if let path = renamingGroup {
                ProductTextEditSheet(
                    title: "グループ名",
                    label: "名前",
                    initialValue: path.last ?? ""
                ) { name in
                    do {
                        try updateDraftThrowing {
                            try $0.renameGroup(path, to: name)
                        }
                    } catch {
                        localError = error.localizedDescription
                    }
                    renamingGroup = nil
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = localError ?? editor.errorMessage {
                ProductInlineError(message: message) {
                    localError = nil
                    editor.errorMessage = nil
                }
            }
        }
    }

    private var currentDraft: ProfileV3TransformTableRows {
        draft ?? ProfileV3TransformTableRows(
            id: tableID,
            title: nil,
            rows: []
        )
    }

    private var ordinaryTitle: String {
        guard let index = editor.transformRows.firstIndex(
            where: { $0.id == tableID }
        ) else {
            return "変換表"
        }
        return currentDraft.ordinaryTitle(position: index)
    }

    private func updateDraft(
        _ mutation: (inout ProfileV3TransformTableRows) -> Void
    ) {
        var next = currentDraft
        mutation(&next)
        draft = next
    }

    private func updateDraftThrowing(
        _ mutation: (inout ProfileV3TransformTableRows) throws -> Void
    ) throws {
        var next = currentDraft
        try mutation(&next)
        draft = next
    }

    private func apply() {
        guard let draft,
              let persistedBaseline
        else {
            return
        }

        let candidate =
            ProfileV3TransformEditPolicy.tablePersistenceCandidate(
                draft: draft,
                persisted: persistedBaseline
            )

        if editor.setTransformTable(candidate) {
            self.persistedBaseline =
                editor.transformRows.first {
                    $0.id == tableID
                }
            localError = nil
        }
    }

    private func rowMatchesSearch(
        _ row: ProfileV3TransformRow
    ) -> Bool {
        guard !searchText.isEmpty else { return false }
        return row.from.localizedCaseInsensitiveContains(searchText)
            || row.to.localizedCaseInsensitiveContains(searchText)
    }
}

private struct ProductTransformRowEditor: View {
    @Binding var row: ProfileV3TransformRow
    let groups: [[String]]
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("変換前", text: $row.from)
                .frame(maxWidth: .infinity)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("変換後", text: $row.to)
                .frame(maxWidth: .infinity)

            Menu {
                Button("グループなし") {
                    row.groupPath = []
                }
                ForEach(groups, id: \.self) { path in
                    Button(path.joined(separator: " / ")) {
                        row.groupPath = path
                    }
                }
            } label: {
                Image(systemName: row.groupPath.isEmpty ? "folder" : "folder.fill")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("グループ")

            Toggle("逆", isOn: $row.reverse)
                .labelsHidden()
                .accessibilityLabel("逆変換")
        }
        .padding(.vertical, 2)
        .background(
            highlighted
                ? Color.accentColor.opacity(0.12)
                : Color.clear
        )
    }
}
