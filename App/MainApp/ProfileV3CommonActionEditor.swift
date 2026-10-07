import SwiftUI
import GestureIMEProfileAuthoring

/// #157 U6 shared ordinary Action presentation.
///
/// This view edits only a local Action draft binding. ProfileDocument mutation,
/// validation and persistence remain owned by the concrete Macro / Rule editor.
struct ProfileV3CommonActionStackEditor: View {
    @ObservedObject var editor: ProfileV3EditorModel
    @Binding var actions: [ProfileActionDraft]
    let sourceEditable: Bool
    var maximumActions: Int = 16

    private var ordinaryEditable: Bool {
        sourceEditable
            && actions.allSatisfy(
                CommonActionOption.supportsOrdinaryEditing
            )
    }

    var body: some View {
        Group {
            if ordinaryEditable {
                if actions.isEmpty {
                    Text("動作なし")
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                }

                ForEach(actions.indices, id: \.self) { index in
                    actionRow(index)
                }

                addActionMenu
                    .disabled(actions.count >= maximumActions)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "詳細設定の動作を保持しています",
                        systemImage: "lock"
                    )
                    .foregroundStyle(.secondary)

                    Text(
                        "通常画面で安全に表現できない動作が含まれるため、この動作列は変更せず保持します。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ index: Int) -> some View {
        let action = actions[index]

        if let option = CommonActionOption.exact(action.actionID) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("動作 \(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Menu {
                        profileV3MoveMenuItems(
                            canMoveUp: index > 0,
                            canMoveDown: index + 1 < actions.count,
                            onMoveUp: {
                                moveAction(index, by: -1)
                            },
                            onMoveDown: {
                                moveAction(index, by: 1)
                            }
                        )

                        Divider()

                        Button("削除", role: .destructive) {
                            actions.remove(at: index)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("動作の操作")
                }

                Menu {
                    ForEach(CommonActionPurpose.allCases) { purpose in
                        let options =
                            CommonActionOption.ordinaryEditorOptions
                                .filter { $0.purpose == purpose }

                        if !options.isEmpty {
                            Section(purpose.title) {
                                ForEach(options) { candidate in
                                    Button(candidate.displayTitle) {
                                        changeAction(
                                            index,
                                            to: candidate
                                        )
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label(
                            option.displayTitle,
                            systemImage: "bolt.fill"
                        )

                        Spacer(minLength: 8)

                        Image(
                            systemName:
                                "chevron.up.chevron.down"
                        )
                        .font(.caption)
                    }
                    .frame(minHeight: 44)
                }

                argumentEditor(
                    index: index,
                    option: option
                )
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(.vertical, 4)
        }
    }

    private var addActionMenu: some View {
        Menu {
            ForEach(CommonActionPurpose.allCases) { purpose in
                let options =
                    CommonActionOption.ordinaryEditorOptions
                        .filter { $0.purpose == purpose }

                if !options.isEmpty {
                    Section(purpose.title) {
                        ForEach(options) { option in
                            Button(option.displayTitle) {
                                addAction(option)
                            }
                        }
                    }
                }
            }
        } label: {
            Label(
                "動作を追加",
                systemImage: "plus.rectangle.on.rectangle"
            )
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private func argumentEditor(
        index: Int,
        option: CommonActionOption
    ) -> some View {
        if option == .layerSet || option == .layerPush {
            Picker(
                option.argumentLabel,
                selection: argumentBinding(index, option)
            ) {
                ForEach(editor.layers) { layer in
                    Text(
                        layer.name?.isEmpty == false
                            ? layer.name!
                            : layer.id
                    )
                    .tag(layer.id)
                }
            }
        } else if option == .macroRun {
            Picker(
                option.argumentLabel,
                selection: argumentBinding(index, option)
            ) {
                ForEach(editor.macros) { macro in
                    Text(macro.id)
                        .tag(macro.id)
                }
            }
        } else if option.argumentKey != nil {
            TextField(
                option.argumentLabel,
                text: argumentBinding(index, option)
            )
            .keyboardType(
                option.integerArgument
                    ? .numbersAndPunctuation
                    : .default
            )
        }
    }

    private func argumentBinding(
        _ index: Int,
        _ option: CommonActionOption
    ) -> Binding<String> {
        Binding(
            get: {
                guard actions.indices.contains(index) else {
                    return ""
                }
                return option.ordinaryArgumentText(
                    from: actions[index]
                ) ?? ""
            },
            set: { text in
                guard actions.indices.contains(index) else {
                    return
                }
                actions[index] =
                    option.makeOrdinaryDraft(
                        argumentText: text,
                        preserving: actions[index]
                    )
            }
        )
    }

    private func addAction(
        _ option: CommonActionOption
    ) {
        actions.append(
            option.makeOrdinaryDraft(
                argumentText:
                    defaultArgument(for: option),
                preserving: nil
            )
        )
    }

    private func changeAction(
        _ index: Int,
        to option: CommonActionOption
    ) {
        guard actions.indices.contains(index) else {
            return
        }

        actions[index] =
            option.makeOrdinaryDraft(
                argumentText:
                    defaultArgument(for: option),
                preserving: nil
            )
    }

    private func moveAction(
        _ index: Int,
        by offset: Int
    ) {
        let destination = index + offset
        guard
            actions.indices.contains(index),
            actions.indices.contains(destination)
        else {
            return
        }

        let action = actions.remove(at: index)
        actions.insert(action, at: destination)
    }

    private func defaultArgument(
        for option: CommonActionOption
    ) -> String {
        switch option {
        case .layerSet, .layerPush:
            editor.layers.first?.id ?? ""
        case .macroRun:
            editor.macros.first?.id ?? ""
        case .editDelete, .cursorMove:
            "1"
        case .conversionSelectCandidate:
            "0"
        default:
            ""
        }
    }
}
