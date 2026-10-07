import SwiftUI
import GestureIMEProfileAuthoring

struct ProductMacroList: View {
    @ObservedObject var editor: ProfileV3EditorModel
    @State private var creating = false
    @State private var duplicating: ProfileV3MacroSummary?
    @State private var deleting: ProfileV3MacroSummary?

    var body: some View {
        List {
            if editor.macros.isEmpty {
                ContentUnavailableView(
                    "マクロはありません",
                    systemImage: "list.bullet.rectangle"
                )
            } else {
                ForEach(editor.macros) { macro in
                    NavigationLink {
                        ProductMacroDetail(
                            editor: editor,
                            macroID: macro.id
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(macro.id)
                            Text("\(macro.actions.count)動作")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleting = macro
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        Button {
                            duplicating = macro
                        } label: {
                            Label("複製", systemImage: "plus.square.on.square")
                        }
                    }
                }
            }
        }
        .navigationTitle("マクロ")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("マクロを追加")
            }
        }
        .sheet(isPresented: $creating) {
            ProductSemanticIDSheet(
                title: "マクロを追加",
                initialID: "",
                confirmTitle: "追加"
            ) { id in
                editor.createMacro(id: id)
            }
        }
        .sheet(item: $duplicating) { macro in
            ProductSemanticIDSheet(
                title: "マクロを複製",
                initialID: macro.id + "-copy",
                confirmTitle: "複製"
            ) { id in
                editor.duplicateMacro(
                    id: macro.id,
                    newID: id
                )
            }
        }
        .confirmationDialog(
            "マクロを削除しますか？",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let deleting {
                    _ = editor.deleteMacro(id: deleting.id)
                }
                deleting = nil
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

private struct ProductMacroDetail: View {
    @ObservedObject var editor: ProfileV3EditorModel
    let macroID: String

    @State private var actions: [ProfileActionDraft] = []
    @State private var loaded = false

    private var macro: ProfileV3MacroSummary? {
        editor.macros.first { $0.id == macroID }
    }

    var body: some View {
        List {
            LabeledContent("識別子") {
                Text(macroID)
                    .textSelection(.enabled)
            }

            if let macro, !macro.actionsEditable {
                Text("このマクロには通常編集で安全に表現できない動作が含まれるため、内容を保持したまま読み取り専用です。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ProductActionSequenceSection(
                    editor: editor,
                    actions: $actions
                )
            }
        }
        .navigationTitle(macroID)
        .toolbar {
            if macro?.actionsEditable != false {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    EditButton()
                    Button("適用") {
                        _ = editor.updateMacro(
                            id: macroID,
                            actions: actions
                        )
                    }
                }
            }
        }
        .onAppear {
            loadIfNeeded()
        }
        .safeAreaInset(edge: .bottom) {
            if let message = editor.errorMessage {
                ProductInlineError(message: message) {
                    editor.errorMessage = nil
                }
            }
        }
    }

    private func loadIfNeeded() {
        guard !loaded, let macro else { return }
        actions = macro.actions
        loaded = true
    }
}
