import SwiftUI
import GestureIMEProfileAuthoring

/// #113 / frozen #95 §F7: truthful advanced/developer landing surface.
///
/// The concrete editor is injected from the root workspace. This view never
/// loads a second Profile document from persistence, so unsaved edits remain
/// owned by the same mutable session used by Edit/Input/Design.
struct ProfileV3AdvancedSettingsView: View {
    @EnvironmentObject private var library: ProfileLibraryModel
    @ObservedObject var editor: ProfileV3EditorModel
    @State private var sheet: AdvancedJSONSheet?

    var body: some View {
        List {
            Section("内部情報") {
                LabeledContent("Profile ID") {
                    Text(editor.profileID)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if let boardID = editor.currentBoardID {
                    LabeledContent("Board ID") {
                        Text(boardID)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                if let layerID = editor.selectedLayerID {
                    LabeledContent("Layer ID") {
                        Text(layerID)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            Section("検証・診断") {
                if editor.validation.valid {
                    Label("Profile は有効です", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Label(
                        ProfileV3DisplayCatalog.validationMessage(code: editor.validation.errorCode),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.red)
                    if let detail = editor.validation.detail {
                        Text(detail)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                LabeledContent("参照元") {
                    Text("\(editor.inboundReferences.count)")
                        .monospacedDigit()
                }
                ForEach(editor.inboundReferences) { reference in
                    Button(reference.path) {
                        editor.openInboundReference(reference)
                    }
                    .font(.caption.monospaced())
                }
            }

            Section("Raw JSON") {
                Button("選択中キーの条件 JSON") {
                    sheet = .resolver
                }
                .disabled(editor.selectedResolverJSON() == nil)

                Button("状態 JSON") {
                    sheet = .states
                }
                Button("変換表 JSON") {
                    sheet = .transformTables
                }
                Button("マクロ JSON") {
                    sheet = .macros
                }
            }

            Section("共有セッション") {
                NavigationLink {
                    ProfileV3OverviewEditorView(library: library, editor: editor)
                        .id(editor.profileID)
                } label: {
                    Label("同じキーボード編集セッションを開く", systemImage: "square.grid.3x3")
                }
                Text("編集・入力・デザイン・詳細設定は同じ未保存状態を共有します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(ProfileV3AppCategory.advanced.title)
        .sheet(item: $sheet) { item in
            advancedJSONEditor(item)
        }
    }

    @ViewBuilder
    private func advancedJSONEditor(_ item: AdvancedJSONSheet) -> some View {
        switch item {
        case .resolver:
            ProfileV3AdvancedJSONEditor(
                title: "条件 JSON",
                initialJSON: editor.selectedResolverJSON() ?? "{}"
            ) { editor.setSelectedResolverJSON($0) }
        case .states:
            ProfileV3AdvancedJSONEditor(
                title: "状態 JSON",
                initialJSON: editor.semanticSectionJSON(.states) ?? "[]"
            ) { editor.setSemanticSectionJSON(.states, text: $0) }
        case .transformTables:
            ProfileV3AdvancedJSONEditor(
                title: "変換表 JSON",
                initialJSON: editor.semanticSectionJSON(.transformTables) ?? "[]"
            ) { editor.setSemanticSectionJSON(.transformTables, text: $0) }
        case .macros:
            ProfileV3AdvancedJSONEditor(
                title: "マクロ JSON",
                initialJSON: editor.semanticSectionJSON(.macros) ?? "[]"
            ) { editor.setSemanticSectionJSON(.macros, text: $0) }
        }
    }
}

private enum AdvancedJSONSheet: String, Identifiable {
    case resolver
    case states
    case transformTables
    case macros

    var id: String { rawValue }
}

private struct ProfileV3AdvancedJSONEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (String) -> Bool
    @State private var text: String

    init(
        title: String,
        initialJSON: String,
        onSave: @escaping (String) -> Bool
    ) {
        self.title = title
        self.onSave = onSave
        _text = State(initialValue: initialJSON)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(8)
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("検証して適用") {
                            if onSave(text) {
                                dismiss()
                            }
                        }
                    }
                }
        }
    }
}
