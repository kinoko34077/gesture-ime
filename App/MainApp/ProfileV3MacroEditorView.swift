import SwiftUI
import GestureIMEProfileAuthoring

struct ProfileV3MacroEditorView: View {
    @ObservedObject var editor: ProfileV3EditorModel
    @State private var localError: String?

    var body: some View {
        List {
            if editor.macros.isEmpty {
                ContentUnavailableView {
                    Label(
                        "マクロはありません",
                        systemImage: "list.bullet.rectangle"
                    )
                } description: {
                    Text(
                        "複数の動作を順番に実行するマクロを追加できます。"
                    )
                } actions: {
                    Button("マクロを追加") {
                        createMacro()
                    }
                }
            } else {
                ForEach(editor.macros) { macro in
                    NavigationLink {
                        ProfileV3MacroDetailView(
                            editor: editor,
                            macro: macro
                        )
                    } label: {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(macro.id)

                            Text(
                                macro.actionsEditable
                                    ? "\(macro.actions.count)個の動作"
                                    : "詳細設定の動作を保持"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .frame(
                            minHeight: 44,
                            alignment: .leading
                        )
                    }
                    .swipeActions(
                        edge: .trailing,
                        allowsFullSwipe: false
                    ) {
                        Button(role: .destructive) {
                            deleteMacro(macro.id)
                        } label: {
                            Label(
                                "削除",
                                systemImage: "trash"
                            )
                        }
                    }
                    .contextMenu {
                        Button {
                            duplicateMacro(macro.id)
                        } label: {
                            Label(
                                "複製",
                                systemImage:
                                    "plus.square.on.square"
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(
            ProfileV3AppCategory.macros.title
        )
        .toolbar {
            ToolbarItemGroup(
                placement: .topBarTrailing
            ) {
                Button {
                    editor.undo()
                } label: {
                    Image(
                        systemName:
                            "arrow.uturn.backward"
                    )
                }
                .disabled(!editor.canUndo)
                .accessibilityLabel("取り消す")

                Button {
                    editor.redo()
                } label: {
                    Image(
                        systemName:
                            "arrow.uturn.forward"
                    )
                }
                .disabled(!editor.canRedo)
                .accessibilityLabel("やり直す")

                Button {
                    createMacro()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("マクロを追加")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let localError {
                ProfileV3InlineAuthoringError(
                    message: localError,
                    correctionHint:
                        "参照中の動作またはマクロを確認して、もう一度操作してください。"
                )
            }
        }
    }

    private func createMacro() {
        if editor.createMacro() == nil {
            captureEditorError(
                fallback: "マクロを追加できません。"
            )
        }
    }

    private func duplicateMacro(_ id: String) {
        if editor.duplicateMacro(id: id) == nil {
            captureEditorError(
                fallback: "マクロを複製できません。"
            )
        }
    }

    private func deleteMacro(_ id: String) {
        if !editor.deleteMacro(id: id) {
            captureEditorError(
                fallback: "マクロを削除できません。"
            )
        }
    }

    private func captureEditorError(
        fallback: String
    ) {
        localError = editor.errorMessage ?? fallback
        editor.errorMessage = nil
    }
}

private struct ProfileV3MacroDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: ProfileV3EditorModel
    let macro: ProfileV3MacroSummary

    @State private var actions: [ProfileActionDraft]
    @State private var localError: String?

    init(
        editor: ProfileV3EditorModel,
        macro: ProfileV3MacroSummary
    ) {
        _editor = ObservedObject(
            wrappedValue: editor
        )
        self.macro = macro
        _actions = State(
            initialValue: macro.actions
        )
    }

    var body: some View {
        Form {
            Section("マクロ") {
                LabeledContent("識別子") {
                    Text(macro.id)
                        .font(
                            .system(
                                .body,
                                design: .monospaced
                            )
                        )
                        .textSelection(.enabled)
                }
            }

            Section {
                ProfileV3CommonActionStackEditor(
                    editor: editor,
                    actions: $actions,
                    sourceEditable:
                        macro.actionsEditable,
                    maximumActions: 32
                )
            } header: {
                Text("動作")
            } footer: {
                if macro.actionsEditable {
                    Text(
                        "上から順に実行します。動作はマクロと条件分岐で同じ編集方法を使います。"
                    )
                }
            }
        }
        .navigationTitle(macro.id)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let localError {
                ProfileV3InlineAuthoringError(
                    message: localError,
                    correctionHint:
                        "現在の編集は残っています。内容を修正して、もう一度保存してください。"
                )
            }
        }
        .toolbar {
            ToolbarItem(
                placement: .confirmationAction
            ) {
                Button("保存") {
                    save()
                }
                .disabled(!macro.actionsEditable)
            }
        }
    }

    private func save() {
        localError = nil

        guard macro.actionsEditable else {
            return
        }

        if editor.updateMacro(
            id: macro.id,
            actions: actions
        ) {
            dismiss()
        } else {
            localError =
                editor.errorMessage
                ?? "マクロを保存できません。"
            editor.errorMessage = nil
        }
    }
}
