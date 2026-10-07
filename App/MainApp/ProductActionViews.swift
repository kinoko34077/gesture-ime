import SwiftUI
import GestureIMEProfileAuthoring

struct ProductActionSequenceSection: View {
    @ObservedObject var editor: ProfileV3EditorModel
    @Binding var actions: [ProfileActionDraft]
    @State private var adding = false

    var body: some View {
        Section("動作") {
            if actions.isEmpty {
                Text("動作なし")
                    .foregroundStyle(.secondary)
            }

            ForEach(actions.indices, id: \.self) { index in
                NavigationLink {
                    ProductActionDetail(
                        editor: editor,
                        action: Binding(
                            get: { actions[index] },
                            set: { actions[index] = $0 }
                        )
                    )
                } label: {
                    let action = actions[index]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(actionTitle(action))
                        if let option = CommonActionOption.exact(action.actionID),
                           let value = option.ordinaryArgumentText(from: action),
                           !value.isEmpty {
                            Text(value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .contextMenu {
                    Button {
                        actions.insert(actions[index], at: index + 1)
                    } label: {
                        Label("複製", systemImage: "plus.square.on.square")
                    }

                    Button {
                        guard index > 0 else { return }
                        actions.swapAt(index, index - 1)
                    } label: {
                        Label("上へ", systemImage: "arrow.up")
                    }
                    .disabled(index == 0)

                    Button {
                        guard index + 1 < actions.count else { return }
                        actions.swapAt(index, index + 1)
                    } label: {
                        Label("下へ", systemImage: "arrow.down")
                    }
                    .disabled(index + 1 >= actions.count)

                    Button(role: .destructive) {
                        actions.remove(at: index)
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
                .accessibilityAction(named: "複製") {
                    actions.insert(actions[index], at: index + 1)
                }
                .accessibilityAction(named: "上へ") {
                    guard index > 0 else { return }
                    actions.swapAt(index, index - 1)
                }
                .accessibilityAction(named: "下へ") {
                    guard index + 1 < actions.count else { return }
                    actions.swapAt(index, index + 1)
                }
            }
            .onMove { source, destination in
                actions.move(
                    fromOffsets: source,
                    toOffset: destination
                )
            }

            Button {
                adding = true
            } label: {
                Label("動作を追加", systemImage: "plus")
            }
        }
        .sheet(isPresented: $adding) {
            ProductNewActionSheet(
                editor: editor
            ) { action in
                actions.append(action)
            }
        }
    }

    private func actionTitle(_ action: ProfileActionDraft) -> String {
        CommonActionOption.exact(action.actionID)?.displayTitle
            ?? action.actionID
    }
}

private struct ProductNewActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: ProfileV3EditorModel
    let onAdd: (ProfileActionDraft) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(CommonActionPurpose.allCases) { purpose in
                    let options = CommonActionOption.ordinaryEditorOptions
                        .filter { $0.purpose == purpose }
                    if !options.isEmpty {
                        Section(purpose.title) {
                            ForEach(options) { option in
                                Button(option.displayTitle) {
                                    onAdd(
                                        option.makeOrdinaryDraft(
                                            argumentText: "",
                                            preserving: nil
                                        )
                                    )
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("動作を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}

private struct ProductActionDetail: View {
    @ObservedObject var editor: ProfileV3EditorModel
    @Binding var action: ProfileActionDraft

    private var option: CommonActionOption? {
        CommonActionOption.exact(action.actionID)
    }

    var body: some View {
        Form {
            if let option,
               CommonActionOption.ordinaryEditorOptions.contains(option) {
                Picker("動作", selection: Binding(
                    get: { option },
                    set: { next in
                        action = next.makeOrdinaryDraft(
                            argumentText: "",
                            preserving: action
                        )
                    }
                )) {
                    ForEach(CommonActionPurpose.allCases) { purpose in
                        Section(purpose.title) {
                            ForEach(
                                CommonActionOption.ordinaryEditorOptions
                                    .filter { $0.purpose == purpose }
                            ) { item in
                                Text(item.displayTitle).tag(item)
                            }
                        }
                    }
                }

                if option.argumentKey != nil {
                    argumentEditor(option)
                }
            } else {
                LabeledContent("動作ID") {
                    Text(action.actionID)
                        .textSelection(.enabled)
                }
                Text("この動作は通常編集で安全に表現できないため、内容を保持したまま読み取り専用で表示しています。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(option?.displayTitle ?? "動作")
    }

    @ViewBuilder
    private func argumentEditor(
        _ option: CommonActionOption
    ) -> some View {
        if option.integerArgument {
            let value = Int(
                option.ordinaryArgumentText(from: action) ?? ""
            ) ?? 0
            Stepper(
                "\(option.argumentLabel): \(value)",
                value: Binding(
                    get: { value },
                    set: { next in
                        action = option.makeOrdinaryDraft(
                            argumentText: String(next),
                            preserving: action
                        )
                    }
                )
            )
        } else if option == .layerSet || option == .layerPush {
            Picker(
                option.argumentLabel,
                selection: Binding(
                    get: {
                        option.ordinaryArgumentText(from: action)
                            ?? editor.layers.first?.id
                            ?? ""
                    },
                    set: {
                        action = option.makeOrdinaryDraft(
                            argumentText: $0,
                            preserving: action
                        )
                    }
                )
            ) {
                ForEach(editor.layers) { layer in
                    Text(layer.name ?? "キーボード面")
                        .tag(layer.id)
                }
            }
        } else if option == .macroRun {
            Picker(
                option.argumentLabel,
                selection: Binding(
                    get: {
                        option.ordinaryArgumentText(from: action)
                            ?? editor.macros.first?.id
                            ?? ""
                    },
                    set: {
                        action = option.makeOrdinaryDraft(
                            argumentText: $0,
                            preserving: action
                        )
                    }
                )
            ) {
                ForEach(editor.macros) { macro in
                    Text(macro.id).tag(macro.id)
                }
            }
        } else {
            TextField(
                option.argumentLabel,
                text: Binding(
                    get: {
                        option.ordinaryArgumentText(from: action) ?? ""
                    },
                    set: {
                        action = option.makeOrdinaryDraft(
                            argumentText: $0,
                            preserving: action
                        )
                    }
                )
            )
        }
    }
}
