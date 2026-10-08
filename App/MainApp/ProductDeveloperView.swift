import Foundation
import SwiftUI
import GestureIMEProfileAuthoring
import GestureIMEProductSettings

struct ProductDeveloperView: View {
    @EnvironmentObject private var productSettings:
        ProductSettingsModel

    @ObservedObject var editor: ProfileV3EditorModel
    @State private var sheet: ProductDeveloperJSONSheet?

    var body: some View {
        List {
            Section("内部ID") {
                LabeledContent("Profile") {
                    Text(editor.profileID)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                if let boardID = editor.currentBoardID {
                    LabeledContent("Board") {
                        Text(boardID)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                LabeledContent("Layer") {
                    Text(editor.selectedLayerID)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section("Profile検証") {
                if editor.validation.valid {
                    Label(
                        "Profileは有効です",
                        systemImage: "checkmark.circle"
                    )
                } else {
                    Label(
                        ProfileV3DisplayCatalog
                            .validationMessage(
                                code:
                                    editor.validation.errorCode
                            ),
                        systemImage:
                            "exclamationmark.triangle"
                    )
                    if let detail = editor.validation.detail {
                        Text(detail)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                LabeledContent("参照元") {
                    Text(
                        "\(editor.inboundReferences.count)"
                    )
                    .monospacedDigit()
                }

                ForEach(editor.inboundReferences) {
                    reference in
                    Text(reference.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section("製品設定 raw") {
                LabeledContent("触覚") {
                    Text(
                        String(
                            format: "%.3f",
                            productSettings
                                .values.hapticStrength
                        )
                    )
                    .monospacedDigit()
                }

                LabeledContent("高さ倍率") {
                    Text(
                        String(
                            format: "%.6f",
                            productSettings
                                .values.keyboardHeightScale
                        )
                    )
                    .monospacedDigit()
                }

                LabeledContent("キー音") {
                    Text(
                        productSettings
                            .values.keySoundEnabled
                            ? "true"
                            : "false"
                    )
                    .monospaced()
                }

                Text(productSettings.deliveryStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("署名・共有領域") {
                let diagnostics =
                    AppGroupRuntimeDiagnosticsProbe
                        .captureMainBundle()

                Text(diagnostics.japaneseDiagnosis)

                Text(diagnostics.report)
                    .font(
                        .system(
                            .caption2,
                            design: .monospaced
                        )
                    )
                    .textSelection(.enabled)

                ShareLink(item: diagnostics.report) {
                    Label(
                        "診断結果を共有",
                        systemImage: "square.and.arrow.up"
                    )
                }
            }

            Section("Raw JSON") {
                Button("選択中キーの条件 JSON") {
                    sheet = .resolver
                }
                .disabled(
                    editor.selectedResolverJSON() == nil
                )

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
        }
        .navigationTitle("開発者")
        .sheet(item: $sheet) { item in
            ProductDeveloperJSONEditor(
                title: item.title,
                initialJSON: json(item),
                errorMessage: $editor.errorMessage
            ) { text in
                apply(item, text: text)
            }
        }
    }

    private func json(
        _ item: ProductDeveloperJSONSheet
    ) -> String {
        switch item {
        case .resolver:
            editor.selectedResolverJSON() ?? "{}"
        case .states:
            editor.semanticSectionJSON(.states) ?? "[]"
        case .transformTables:
            editor.semanticSectionJSON(
                .transformTables
            ) ?? "[]"
        case .macros:
            editor.semanticSectionJSON(.macros) ?? "[]"
        }
    }

    private func apply(
        _ item: ProductDeveloperJSONSheet,
        text: String
    ) -> Bool {
        switch item {
        case .resolver:
            return editor.setSelectedResolverJSON(text)

        case .states:
            return editor.setSemanticSectionJSON(
                .states,
                text: text
            )

        case .transformTables:
            return editor.setSemanticSectionJSON(
                .transformTables,
                text: text
            )

        case .macros:
            return editor.setSemanticSectionJSON(
                .macros,
                text: text
            )
        }
    }
}

private enum ProductDeveloperJSONSheet:
    String,
    Identifiable {
    case resolver
    case states
    case transformTables
    case macros

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resolver: "条件 JSON"
        case .states: "状態 JSON"
        case .transformTables: "変換表 JSON"
        case .macros: "マクロ JSON"
        }
    }
}

private struct ProductDeveloperJSONEditor: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onSave: (String) -> Bool

    @Binding var errorMessage: String?
    @State private var text: String

    init(
        title: String,
        initialJSON: String,
        errorMessage: Binding<String?>,
        onSave: @escaping (String) -> Bool
    ) {
        self.title = title
        self.onSave = onSave
        _errorMessage = errorMessage
        _text = State(initialValue: initialJSON)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(
                    .system(
                        .body,
                        design: .monospaced
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(8)
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(
                        placement: .cancellationAction
                    ) {
                        Button("キャンセル") {
                            errorMessage = nil
                            dismiss()
                        }
                    }

                    ToolbarItem(
                        placement: .confirmationAction
                    ) {
                        Button("検証して適用") {
                            errorMessage = nil
                            if onSave(text) {
                                dismiss()
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let errorMessage {
                        ProductInlineError(
                            message: errorMessage
                        ) {
                            self.errorMessage = nil
                        }
                    }
                }
        }
    }
}
